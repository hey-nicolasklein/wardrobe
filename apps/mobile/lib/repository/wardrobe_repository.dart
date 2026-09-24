import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/utils/immutable_json.dart';

class ItemCommand {
  ItemCommand(this.path, this.method, Map<String, dynamic> fields)
    : body = immutableJson({
        ...fields,
        'idempotencyKey': List.generate(
          24,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      });

  factory ItemCommand.edit(WardrobeItem item, Map<String, dynamic> changes) =>
      ItemCommand('v1/wardrobe-items/${item.id}', 'PATCH', {
        ...changes,
        'expectedRecordVersion': item.recordVersion,
      });
  factory ItemCommand.delete(WardrobeItem item) => ItemCommand(
    'v1/wardrobe-items/${item.id}',
    'DELETE',
    {'expectedRecordVersion': item.recordVersion},
  );
  factory ItemCommand.restore(WardrobeItem item, String version) => ItemCommand(
    'v1/wardrobe-items/${item.id}/shelf-image-versions/$version/restore',
    'POST',
    {'expectedRecordVersion': item.recordVersion},
  );
  factory ItemCommand.generate(String id, String quality, String? feedback) =>
      ItemCommand('v1/generations', 'POST', {
        'wardrobeItemId': id,
        'quality': quality,
        'size': '816x816',
        'autoKeep': true,
        'feedback': feedback,
      });
  final String path;
  final String method;
  final Map<String, dynamic> body;
}

/// Domain snapshot stores a full detail separately from its newer list record.
class CachedItem {
  const CachedItem(this.item, this.detail);
  factory CachedItem.fromRecord(WardrobeRecord row) => CachedItem(
    WardrobeItem.fromJson(jsonDecode(row.itemJson) as Map<String, dynamic>),
    row.detailJson == null
        ? null
        : ItemDetail.fromJson(
            jsonDecode(row.detailJson!) as Map<String, dynamic>,
          ),
  );
  final WardrobeItem item;
  final ItemDetail? detail;
  String get thumbnailIdentity => 'preview:${item.id}:${item.recordVersion}';
  String get thumbnailPath =>
      'v1/wardrobe-items/${item.id}/preview?v=${item.recordVersion}';
}

class WardrobeRepository {
  WardrobeRepository(this.database, this.api, this.scope, this.media);
  final AppDatabase database;
  final FormApi? api;
  final String scope;
  final MediaRepository media;
  int _revision = 0;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  Future<List<CachedItem>> cached() async =>
      (await (database.select(
            database.wardrobeRecords,
          )..where((r) => r.scope.equals(scope))).get())
          .map(CachedItem.fromRecord)
          .toList();
  Future<bool> hasSnapshot() async =>
      (await (database.select(database.collectionSummaries)..where(
            (r) =>
                r.scope.equals(scope) & r.collection.equals('wardrobe-records'),
          ))
          .getSingleOrNull()) !=
      null;

  Future<ItemDetail?> cachedDetail(String id) async =>
      (await cached()).where((r) => r.item.id == id).firstOrNull?.detail;

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) {
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    return api!.request(path, method: method, data: data);
  }

  Future<List<CachedItem>> refresh() async {
    final revision = _revision;
    final response = await _request('v1/wardrobe-items');
    final List<WardrobeItem> items;
    try {
      items = (response['wardrobeItems'] as List<dynamic>)
          .map((v) => WardrobeItem.fromJson(v as Map<String, dynamic>))
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
              collection: 'wardrobe-records',
              count: items.length,
              updatedAt: DateTime.now(),
            ),
          );
      await (database.delete(database.wardrobeRecords)..where(
            (r) => r.scope.equals(scope) & r.id.isNotIn(items.map((i) => i.id)),
          ))
          .go();
      for (final item in items) {
        await database
            .into(database.wardrobeRecords)
            .insertOnConflictUpdate(
              WardrobeRecordsCompanion.insert(
                scope: scope,
                id: item.id,
                itemJson: jsonEncode(item.toJson()),
              ),
            );
      }
    });
    final records = await cached();
    unawaited(_prefetch(records));
    return records;
  }

  Future<void> _prefetch(List<CachedItem> records) async {
    for (final record in records) {
      await media.load(
        record.thumbnailIdentity,
        previewPath: record.thumbnailPath,
      );
    }
  }

  Future<ItemDetail> detail(String id) async {
    final response = await _request('v1/wardrobe-items/$id');
    final ItemDetail detail;
    try {
      detail = ItemDetail.fromJson(response);
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
    _revision++;
    await database
        .into(database.wardrobeRecords)
        .insertOnConflictUpdate(
          WardrobeRecordsCompanion.insert(
            scope: scope,
            id: id,
            itemJson: jsonEncode(detail.wardrobeItem.toJson()),
            detailJson: Value(jsonEncode(detail.toJson())),
          ),
        );
    _changes.add(null);
    return detail;
  }

  Future<void> execute(String id, ItemCommand command) async {
    await _request(command.path, method: command.method, data: command.body);
    if (command.method == 'DELETE') {
      _revision++;
      await (database.delete(
        database.wardrobeRecords,
      )..where((r) => r.scope.equals(scope) & r.id.equals(id))).go();
    } else {
      await detail(id);
    }
    if (command.method == 'DELETE') _changes.add(null);
  }

  Future<void> close() => _changes.close();
}
