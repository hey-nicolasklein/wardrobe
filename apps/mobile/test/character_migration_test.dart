import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/repository/character_sheet_repository.dart';
import 'package:form_mobile/services/app_database.dart';

import 'support/character_fixtures.dart';

void main() {
  test(
    'v4 migration adds references while retaining preferences and looks',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (db) {
            db
              ..execute(
                'CREATE TABLE preferences (key TEXT NOT NULL PRIMARY KEY, '
                'value TEXT NOT NULL)',
              )
              ..execute("INSERT INTO preferences VALUES ('language', 'en')")
              ..execute(
                'CREATE TABLE look_records (scope TEXT NOT NULL, '
                'id TEXT NOT NULL, look_json TEXT NOT NULL, '
                'created_at INTEGER NOT NULL, PRIMARY KEY(scope, id))',
              )
              ..execute(
                "INSERT INTO look_records VALUES ('test', 'look-1', '{}', 1)",
              )
              ..execute('PRAGMA user_version = 4');
          },
        ),
      );
      addTearDown(database.close);
      expect(await database.select(database.characterRecords).get(), isEmpty);
      expect(await database.preference('language'), 'en');
      expect(
        (await database.select(database.lookRecords).get()).single.id,
        'look-1',
      );
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        5,
      );
    },
  );

  test(
    'pending and failed references survive SQLite close and reopen',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'form-reference-cache-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/form.sqlite');
      final first = AppDatabase(NativeDatabase(file));
      final api = CharacterApi()
        ..sheets = [
          characterJson(state: 'processing'),
          characterJson(id: 'failed', state: 'failed'),
        ];
      final initial = CharacterSheetRepository(
        api,
        database: first,
        scope: 'test',
      );
      await initial.fetch();
      await initial.close();
      await first.close();
      final second = AppDatabase(NativeDatabase(file));
      final restored = CharacterSheetRepository(
        null,
        database: second,
        scope: 'test',
      );
      addTearDown(() async {
        await restored.close();
        await second.close();
      });
      expect(
        (await restored.cached()).map((s) => s.state),
        containsAll(['processing', 'failed']),
      );
    },
  );
}
