import 'dart:io';

import 'package:form_mobile/repository/character_draft_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/services/app_database.dart';

/// Clears local wardrobe data after a successful server reset or for tests.
class AccountCacheRepository {
  AccountCacheRepository(
    this.database,
    this.scope,
    this.media,
    this.intakeDirectory,
    this.characterDrafts,
  );

  final AppDatabase database;
  final String scope;
  final MediaRepository media;
  final Directory intakeDirectory;
  final CharacterDraftRepository characterDrafts;

  Future<void> clearAfterReset() async {
    await database.clearAccountCache(scope);
    await media.clearScope();
    await _clearIntakeFiles();
    await characterDrafts.clearLocalDraft();
  }

  Future<void> _clearIntakeFiles() async {
    if (intakeDirectory.existsSync()) {
      await intakeDirectory.delete(recursive: true);
    }
  }
}
