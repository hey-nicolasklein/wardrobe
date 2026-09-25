import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/services/app_database.dart';

void main() {
  test('v3 migration adds look_records and keeps wardrobe data', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (db) {
          db
            ..execute(
              'CREATE TABLE preferences '
              '(key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
            )
            ..execute(
              'CREATE TABLE collection_summaries (scope TEXT NOT NULL, '
              'collection TEXT NOT NULL, count INTEGER NOT NULL, '
              'updated_at INTEGER NOT NULL, PRIMARY KEY(scope, collection))',
            )
            ..execute(
              'CREATE TABLE media_cache_entries (scope TEXT NOT NULL, '
              'asset_id TEXT NOT NULL, local_path TEXT NOT NULL, '
              'byte_count INTEGER NOT NULL, last_accessed_at INTEGER NOT NULL, '
              'protected INTEGER NOT NULL DEFAULT 0, '
              'PRIMARY KEY(scope, asset_id))',
            )
            ..execute(
              'CREATE TABLE wardrobe_records '
              '(scope TEXT NOT NULL, id TEXT NOT NULL, '
              'item_json TEXT NOT NULL, detail_json TEXT, '
              'PRIMARY KEY(scope, id))',
            )
            ..execute(
              'INSERT INTO wardrobe_records '
              "VALUES ('test', 'item-1', '{}', NULL)",
            )
            ..execute(
              'CREATE TABLE intake_records '
              '(scope TEXT NOT NULL, id TEXT NOT NULL, '
              'draft_json TEXT NOT NULL, PRIMARY KEY(scope, id))',
            )
            ..execute('PRAGMA user_version = 3');
        },
      ),
    );
    addTearDown(database.close);
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    expect(
      tables.map((row) => row.read<String>('name')),
      contains('look_records'),
    );
    expect(await database.select(database.wardrobeRecords).get(), hasLength(1));
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 5);
  });
}
