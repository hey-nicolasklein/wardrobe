import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/repository/account_cache_repository.dart';
import 'package:form_mobile/repository/character_draft_repository.dart';
import 'package:form_mobile/repository/character_sheet_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';
import 'package:form_mobile/services/photo_preparation.dart';

void main() {
  test('clearAfterReset keeps language and quality preferences', () async {
    final directory = await Directory.systemTemp.createTemp('form-account-');
    addTearDown(() => directory.delete(recursive: true));
    final database = AppDatabase(
      NativeDatabase(File('${directory.path}/db.sqlite')),
    );
    addTearDown(database.close);
    await database.setPreference('language', 'en');
    await database.setPreference('feed-quality', 'high');
    await database.setPreference('wardrobe-quality', 'medium');
    await database.setPreference('look-liked-1', 'true');
    await database.setPreference('look-starts', '{}');
    const scope = 'https://example.test';
    await database
        .into(database.lookRecords)
        .insert(
          LookRecordsCompanion.insert(
            scope: scope,
            id: 'look-1',
            lookJson: '{}',
            createdAt: DateTime.utc(2026),
          ),
        );
    final mediaDir = Directory('${directory.path}/media');
    final media = MediaRepository(database, null, scope, mediaDir);
    final characterDrafts = CharacterDraftRepository(
      CharacterSheetRepository(
        null,
        database: database,
        scope: scope,
        media: media,
      ),
      Directory('${directory.path}/character'),
      PhotoPreparation(),
    );
    final accountCache = AccountCacheRepository(
      database,
      scope,
      media,
      Directory('${directory.path}/intake'),
      characterDrafts,
    );
    await accountCache.clearAfterReset();
    expect(await database.preference('language'), 'en');
    expect(await database.preference('feed-quality'), 'high');
    expect(await database.preference('wardrobe-quality'), 'medium');
    expect(await database.preference('look-liked-1'), isNull);
    expect(await database.preference('look-starts'), isNull);
    expect(
      await (database.select(
        database.lookRecords,
      )..where((r) => r.scope.equals(scope))).get(),
      isEmpty,
    );
  });
}
