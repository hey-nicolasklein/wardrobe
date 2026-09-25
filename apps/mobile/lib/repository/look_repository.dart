import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:form_mobile/features/feed/look_commands.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_json.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

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
  static const _savedPrefix = 'look-saved-';

  Future<List<CachedLook>> cached() async =>
      (await (database.select(database.lookRecords)
                ..where((r) => r.scope.equals(scope))
                ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
              .get())
          .map(CachedLook.fromRecord)
          .toList();

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
      final assetId = record.look.assetId;
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
