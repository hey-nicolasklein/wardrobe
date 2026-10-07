import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:form_mobile/features/feed/look_commands.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_json.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/idempotency_key.dart';

class CachedLook {
  const CachedLook(this.look);

  factory CachedLook.fromRecord(LookRecord row) => CachedLook(
    Look.fromJson(
      normalizeLookJson(
        jsonDecode(row.lookJson) as Map<String, dynamic>,
      ),
    ),
  );

  final Look look;

  String get previewIdentity =>
      look.assetId == null ? 'look:${look.id}' : 'asset:${look.assetId!}';

  String previewPath(String assetId) => 'v1/assets/$assetId/content';
}

class LookRepository {
  LookRepository(this.database, this.api, this.scope, this.media);

  final AppDatabase database;
  final FormApi? api;
  final String scope;
  final MediaRepository media;
  int _revision = 0;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  static const _startsKey = 'look-starts';
  static const _likedPrefix = 'look-liked-';
  static const _heartsUploadedKey = 'look-hearts-uploaded';
  static const _savedPrefix = 'look-saved-';

  Future<List<CachedLook>> cached() async =>
      (await (database.select(database.lookRecords)
                ..where((r) => r.scope.equals(scope))
                ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
              .get())
          .map(CachedLook.fromRecord)
          .toList();

  /// The user's try-on photos, newest first. Reusing one keeps new try-ons
  /// comparable with the old ones. Offline, the photos of cached try-on looks
  /// stand in.
  Future<List<String>> tryOnBases() async {
    try {
      final response = await _request('v1/try-on-photos');
      return [
        for (final photo in response['photos'] as List<dynamic>)
          (photo as Map<String, dynamic>)['assetId'] as String,
      ];
    } on FormApiException {
      return [
        ...{
          for (final cached in await cached())
            if (cached.look.baseAssetId != null) cached.look.baseAssetId!,
        },
      ];
    }
  }

  /// Deletes a try-on photo and its file. Finished try-on looks stay.
  Future<void> deleteTryOnPhoto(String assetId) =>
      _request('v1/try-on-photos/$assetId', method: 'DELETE');

  /// Hearts a look on the server and in the cached copy.
  Future<void> setLiked(String lookId, {required bool liked}) async {
    await _request(
      'v1/looks/$lookId/like',
      method: 'PUT',
      data: {'liked': liked},
    );
    final row =
        await (database.select(database.lookRecords)..where(
              (r) => r.scope.equals(scope) & r.id.equals(lookId),
            ))
            .getSingleOrNull();
    if (row != null) {
      final json = jsonDecode(row.lookJson) as Map<String, dynamic>
        ..['liked'] = liked;
      await (database.update(database.lookRecords)..where(
            (r) => r.scope.equals(scope) & r.id.equals(lookId),
          ))
          .write(LookRecordsCompanion(lookJson: Value(jsonEncode(json))));
    }
    _changes.add(null);
  }

  /// Hearts used to live only on the phone. Uploads them once, so they count
  /// toward the feed weighting too.
  Future<void> uploadLocalHearts(Iterable<Look> looks) async {
    if (await database.preference(_heartsUploadedKey) == 'true') return;
    for (final look in looks) {
      if (!look.liked && await lookMarked(look.id, liked: true)) {
        await setLiked(look.id, liked: true);
      }
    }
    await database.setPreference(_heartsUploadedKey, 'true');
  }

  /// Why the feed picks its shot types: weights, hearts, recent and hidden.
  Future<List<Map<String, dynamic>>> shotWeights() async =>
      ((await _request('v1/look-shots/weights'))['shots'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

  /// Shot types the user asked to see less of.
  Future<List<String>> hiddenShots() async =>
      ((await _request('v1/look-shots'))['hiddenShots'] as List<dynamic>)
          .cast<String>();

  Future<List<String>> setShotHidden(
    String shot, {
    required bool hidden,
  }) async =>
      ((await _request(
                'v1/look-shots/$shot',
                method: 'PUT',
                data: {'hidden': hidden},
              ))['hiddenShots']
              as List<dynamic>)
          .cast<String>();

  /// Uploads a photo of the user as a try-on base and returns its asset id.
  Future<String> uploadTryOnPhoto(Uint8List jpeg) async {
    final (:assetId, sourcePhotoId: _) = await _uploadSourcePhoto(
      jpeg,
      'try-on.jpg',
    );
    // Kept in the try-on photo list even before a try-on uses it.
    await _request(
      'v1/try-on-photos',
      method: 'POST',
      data: {'assetId': assetId},
    );
    return assetId;
  }

  /// Saves [itemIds] as a look laid out flat. Free. Returns the new look id.
  Future<String> createCombination(
    List<String> itemIds, {
    String? occasion,
    String? idempotencyKey,
  }) async {
    final lookId = await executeCreate(
      LookCommand('v1/looks/combinations', 'POST', {
        'itemIds': itemIds,
        'occasion': occasion,
        'idempotencyKey': ?idempotencyKey,
      }),
    );
    await refreshAndNotify();
    return lookId;
  }

  /// Uploads a photo the user wore an outfit in and keeps it as a look. The
  /// server detects its pieces in the background. With [lookId], the photo
  /// is added to that combination instead. Returns the look id.
  Future<String> createPhotoLook(Uint8List jpeg, {String? lookId}) async {
    final sourcePhotoId = (await _uploadSourcePhoto(
      jpeg,
      'look.jpg',
    )).sourcePhotoId;
    final created = await executeCreate(
      LookCommand('v1/looks/photos', 'POST', {
        'sourcePhotoId': sourcePhotoId,
        'lookId': ?lookId,
        // Keyed by the uploaded photo, so a retried request never adds it twice.
        'idempotencyKey': 'photo-look-$sourcePhotoId',
      }),
    );
    await refreshAndNotify();
    return created;
  }

  /// Replaces the pieces of a combination or photo look.
  Future<void> setItems(String lookId, List<String> itemIds) async {
    await _request(
      'v1/looks/$lookId/items',
      method: 'PUT',
      data: {'itemIds': itemIds},
    );
    await refreshAndNotify();
  }

  /// Puts an AI image on top of the combination or photo look [lookId]: `try-on` on
  /// [baseAssetId], or an `inspiration`. Paid. Returns the image's look id.
  Future<String> createImage(
    String lookId, {
    required String mode,
    required String idempotencyKey,
    String? baseAssetId,
    String quality = 'low',
    String? style,
  }) async {
    final imageId = await executeCreate(
      LookCommand('v1/looks/$lookId/images', 'POST', {
        'mode': mode,
        'baseAssetId': ?baseAssetId,
        'style': ?style,
        'quality': quality,
        'idempotencyKey': idempotencyKey,
      }),
    );
    await refreshAndNotify();
    return imageId;
  }

  /// Creates a wardrobe piece from [piece], detected on a photo look, and
  /// orders its catalog image. Returns the piece's id.
  Future<String> addFoundPiece(
    LookFoundPiece piece, {
    required String quality,
  }) async {
    final created = await _request(
      'v1/wardrobe-items',
      method: 'POST',
      data: {
        'detectionProposalId': piece.id,
        'state': 'owning',
        'idempotencyKey': 'found-${piece.id}',
      },
    );
    final itemId =
        (created['wardrobeItem'] as Map<String, dynamic>)['id'] as String;
    await _request(
      'v1/generations',
      method: 'POST',
      data: {
        'wardrobeItemId': itemId,
        'quality': quality,
        'size': '816x816',
        'autoKeep': true,
        'idempotencyKey': 'found-image-${piece.id}',
      },
    );
    return itemId;
  }

  /// Keeps a proposal's outfit as a combination. Free.
  Future<void> keepProposal(String lookId) async {
    await _request('v1/looks/$lookId/keep', method: 'POST', data: {});
    await refreshAndNotify();
  }

  Future<({String assetId, String sourcePhotoId})> _uploadSourcePhoto(
    Uint8List jpeg,
    String fileName,
  ) async {
    final intent = await _request(
      'v1/source-photos/upload-intents',
      method: 'POST',
      data: {
        'fileName': fileName,
        'contentType': 'image/jpeg',
        'byteSize': jpeg.length,
      },
    );
    await api!.upload(
      intent['uploadUrl'] as String,
      jpeg,
      intent['headers'] as Map<String, dynamic>,
      (_, _) {},
    );
    final completed = await _request(
      'v1/source-photos/complete',
      method: 'POST',
      data: {
        'assetId': intent['assetId'],
        'idempotencyKey': newIdempotencyKey(),
      },
    );
    return (
      assetId: (completed['asset'] as Map<String, dynamic>)['id'] as String,
      sourcePhotoId:
          (completed['sourcePhoto'] as Map<String, dynamic>)['id'] as String,
    );
  }

  Future<bool> hasSnapshot() async =>
      (await (database.select(database.collectionSummaries)..where(
            (r) => r.scope.equals(scope) & r.collection.equals('look-records'),
          ))
          .getSingleOrNull()) !=
      null;

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) {
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    return api!.request(path, method: method, data: data);
  }

  Future<List<CachedLook>> refresh() async {
    final revision = _revision;
    final response = await _request('v1/looks');
    final rawLooks = response['looks'];
    if (rawLooks is! List<dynamic>) {
      throw const FormApiException(ApiFailure.incompatible);
    }
    final List<Look> looks;
    try {
      looks = rawLooks
          .map(
            (v) => Look.fromJson(normalizeLookJson(v as Map<String, dynamic>)),
          )
          .toList();
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
    await database.transaction(() async {
      if (revision != _revision) return;
      await database
          .into(database.collectionSummaries)
          .insertOnConflictUpdate(
            CollectionSummariesCompanion.insert(
              scope: scope,
              collection: 'look-records',
              count: looks.length,
              updatedAt: DateTime.now(),
            ),
          );
      await (database.delete(database.lookRecords)..where(
            (r) => r.scope.equals(scope) & r.id.isNotIn(looks.map((l) => l.id)),
          ))
          .go();
      for (final look in looks) {
        await database
            .into(database.lookRecords)
            .insertOnConflictUpdate(
              LookRecordsCompanion.insert(
                scope: scope,
                id: look.id,
                lookJson: jsonEncode(look.toJson()),
                createdAt: look.createdAt,
              ),
            );
      }
    });
    final records = await cached();
    unawaited(_prefetch(records));
    return records;
  }

  Future<void> refreshAndNotify() async {
    await refresh();
    _changes.add(null);
  }

  Future<void> _prefetch(List<CachedLook> records) async {
    for (final record in records) {
      final assetId = record.look.cardAssetId;
      if (assetId == null) continue;
      await media.load(assetId, previewPath: record.previewPath(assetId));
    }
  }

  /// Creates a look, remembers which pieces it started from so its planning
  /// card can show them, and refreshes the feed. Returns the new look id.
  Future<String> create(LookCommand command, List<String> startItemIds) async {
    final lookId = await executeCreate(command);
    await rememberLookStart(lookId, startItemIds);
    await refreshAndNotify();
    return lookId;
  }

  Future<String> executeCreate(LookCommand command) async {
    final response = await _request(
      command.path,
      method: command.method,
      data: command.body,
    );
    final lookId = response['lookId'];
    if (lookId is! String || lookId.isEmpty) {
      throw const FormApiException(ApiFailure.incompatible);
    }
    return lookId;
  }

  Future<void> execute(LookCommand command) async {
    await _request(command.path, method: command.method, data: command.body);
    final deletedId = command.lookId;
    if (deletedId != null) {
      _revision++;
      await (database.delete(
        database.lookRecords,
      )..where((r) => r.scope.equals(scope) & r.id.equals(deletedId))).go();
      _changes.add(null);
    } else {
      await refreshAndNotify();
    }
  }

  /// Plans [count] outfits without rendering them. [body] is a create
  /// command's body. Without [append] they replace the open proposals;
  /// with it they join them, minus [discardLookIds].
  Future<void> propose(
    Map<String, dynamic> body, {
    int count = 3,
    bool append = false,
    List<String> excludedItemIds = const [],
    List<String> discardLookIds = const [],
  }) => _request(
    'v1/looks/proposals',
    method: 'POST',
    data: {
      for (final entry in body.entries)
        if (const {
          'exactItemIds',
          'categories',
          'occasion',
          'style',
          'completion',
          'idempotencyKey',
        }.contains(entry.key))
          entry.key: entry.value,
      'count': count,
      if (append) 'append': true,
      if (excludedItemIds.isNotEmpty) 'excludedItemIds': excludedItemIds,
      if (discardLookIds.isNotEmpty) 'discardLookIds': discardLookIds,
    },
  );

  /// The open proposals, newest first, see [propose].
  Future<List<Look>> proposals() async {
    final response = await _request('v1/looks/proposals');
    try {
      return [
        for (final raw in response['looks'] as List<dynamic>)
          Look.fromJson(normalizeLookJson(raw as Map<String, dynamic>)),
      ];
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
  }

  /// Applies swipe marks to the open proposals in place and returns them.
  /// [except] proposals stay as they are.
  Future<List<Look>> adjustProposals({
    List<String> keep = const [],
    List<String> exclude = const [],
    List<String> except = const [],
  }) async {
    final response = await _request(
      'v1/looks/proposals/adjust',
      method: 'POST',
      data: {
        'keepItemIds': keep,
        'excludeItemIds': exclude,
        if (except.isNotEmpty) 'exceptLookIds': except,
      },
    );
    try {
      return [
        for (final raw in response['looks'] as List<dynamic>)
          Look.fromJson(normalizeLookJson(raw as Map<String, dynamic>)),
      ];
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
  }

  /// Renders a picked proposal. It then develops in the feed like any look.
  Future<void> render(String lookId, {required String quality}) async {
    await _request(
      'v1/looks/$lookId/render',
      method: 'POST',
      data: {'quality': quality, 'idempotencyKey': newIdempotencyKey()},
    );
    await refreshAndNotify();
  }

  Future<Map<String, List<String>>> loadLookStarts() async {
    final raw = await database.preference(_startsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(
          key,
          (value as List<dynamic>).map((entry) => entry as String).toList(),
        ),
      );
    } on Object {
      return {};
    }
  }

  Future<void> rememberLookStart(String lookId, List<String> itemIds) async {
    final starts = await loadLookStarts();
    starts[lookId] = List<String>.from(itemIds);
    await database.setPreference(_startsKey, jsonEncode(starts));
  }

  Future<bool> lookMarked(String lookId, {required bool liked}) async {
    final value = await database.preference(
      (liked ? _likedPrefix : _savedPrefix) + lookId,
    );
    return value == 'true';
  }

  Future<void> setLookMarked(
    String lookId, {
    required bool liked,
    required bool marked,
  }) async {
    await database.setPreference(
      (liked ? _likedPrefix : _savedPrefix) + lookId,
      marked.toString(),
    );
    _changes.add(null);
  }

  Future<void> close() => _changes.close();
}
