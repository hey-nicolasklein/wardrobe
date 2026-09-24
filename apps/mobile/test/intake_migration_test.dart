import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/services/app_database.dart';

void main() {
  test('v2 upgrade adds drafts without changing wardrobe snapshots', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (db) {
          db
            ..execute(
              'CREATE TABLE preferences '
              '(key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
            )
            ..execute("INSERT INTO preferences VALUES ('language', 'de')")
            ..execute(
              'CREATE TABLE wardrobe_records (scope TEXT NOT NULL, '
              'id TEXT NOT NULL, item_json TEXT NOT NULL, detail_json TEXT, '
              'PRIMARY KEY(scope, id))',
            )
            ..execute(
              'INSERT INTO wardrobe_records VALUES '
              "('test', 'item', '{}', '{}')",
            )
            ..execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(database.close);
    expect(await database.preference('language'), 'de');
    final record =
        (await database.select(database.wardrobeRecords).get()).single;
    expect(record.id, 'item');
    expect(record.detailJson, '{}');
    expect(await database.select(database.intakeRecords).get(), isEmpty);
  });
}
