import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/services/app_database.dart';

void main() {
  test('v1 migration preserves preferences and media', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (db) {
          db
            ..execute(
              'CREATE TABLE preferences '
              '(key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
            )
            ..execute("INSERT INTO preferences VALUES ('language', 'en')")
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
              'INSERT INTO media_cache_entries VALUES '
              "('test', 'draft', '/draft', 42, 0, 1)",
            )
            ..execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(database.close);
    expect(await database.preference('language'), 'en');
    expect(
      (await database.select(database.mediaCacheEntries).get())
          .single
          .protected,
      isTrue,
    );
    expect(await database.select(database.wardrobeRecords).get(), isEmpty);
  });
}
