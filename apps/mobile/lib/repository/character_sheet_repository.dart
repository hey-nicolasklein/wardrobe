import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/form_api.dart';

class CharacterSheetRepository {
  CharacterSheetRepository(
    this.api, {
    required this.database,
    required this.scope,
    this.media,
  });

  final FormApi? api;
  final AppDatabase database;
  final String scope;
  final MediaRepository? media;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  int _revision = 0;
  int _fetchId = 0;

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) {
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    return api!.request(path, method: method, data: data);
  }

  Future<List<CharacterSheet>> cached() async {
    final rows = await (database.select(
      database.characterRecords,
    )..where((r) => r.scope.equals(scope))).get();
    return sort(
      rows
          .map(
            (r) => CharacterSheet.fromJson(
              jsonDecode(r.sheetJson) as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }

  static List<CharacterSheet> sort(List<CharacterSheet> sheets) =>
      sheets..sort((a, b) {
        final date = b.createdAt.compareTo(a.createdAt);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });

  Future<List<CharacterSheet>> fetch() async {
    final revision = _revision;
    final fetchId = ++_fetchId;
    final response = await request('v1/character-sheets');
    final List<CharacterSheet> sheets;
    try {
      sheets = sort(
        (response['characterSheets'] as List<dynamic>)
            .map((v) => CharacterSheet.fromJson(v as Map<String, dynamic>))
            .toList(),
      );
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
    await database.transaction(() async {
      if (revision != _revision || fetchId != _fetchId) return;
      await (database.delete(
        database.characterRecords,
      )..where((r) => r.scope.equals(scope))).go();
      for (final sheet in sheets) {
        await database
            .into(database.characterRecords)
            .insert(
              CharacterRecordsCompanion.insert(
                scope: scope,
                id: sheet.id,
                sheetJson: jsonEncode(sheet.toJson()),
              ),
            );
      }
    });
    final records = await cached();
    if (!_changes.isClosed) _changes.add(null);
    unawaited(_prefetch(records));
    return records;
  }

  Future<void> _prefetch(List<CharacterSheet> sheets) async {
    for (final sheet in sheets) {
      if (sheet.assetId != null) {
        await media?.load(
          sheet.assetId!,
          previewPath: 'v1/assets/${sheet.assetId}/content',
        );
      }
    }
  }

  Future<CharacterSheet?> activeReady() async =>
      (await fetch()).where((s) => s.isActiveReady).firstOrNull;

  Future<void> activate(String id, String key) async {
    await request(
      'v1/character-sheets/$id/activate',
      method: 'POST',
      data: {'idempotencyKey': key},
    );
    _revision++;
    await database.transaction(() async {
      for (final sheet in await cached()) {
        final json = sheet.toJson()..['active'] = sheet.id == id;
        await (database.update(
          database.characterRecords,
        )..where((r) => r.scope.equals(scope) & r.id.equals(sheet.id))).write(
          CharacterRecordsCompanion(sheetJson: Value(jsonEncode(json))),
        );
      }
    });
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> delete(String id) async {
    try {
      await request('v1/character-sheets/$id', method: 'DELETE');
    } on FormApiException catch (error) {
      // A lost successful DELETE response can be retried safely.
      if (error.code != 'wardrobe-item-not-found') rethrow;
    }
    _revision++;
    await (database.delete(
      database.characterRecords,
    )..where((r) => r.scope.equals(scope) & r.id.equals(id))).go();
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<String> create(String assetId, String note, String key) async {
    final data = await request(
      'v1/character-sheets',
      method: 'POST',
      data: {
        'referenceAssetIds': [assetId],
        'note': note.trim().isEmpty ? null : note.trim(),
        'idempotencyKey': key,
      },
    );
    final id = data['characterSheetId'];
    if (id is! String || id.isEmpty) {
      throw const FormApiException(ApiFailure.incompatible);
    }
    _revision++;
    return id;
  }

  Future<void> close() => _changes.close();
}
