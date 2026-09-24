import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/settings/language_cubit.dart';
import 'package:form_mobile/repository/preferences_repository.dart';
import 'package:form_mobile/services/app_database.dart';

void main() {
  test('language changes persist across database and Cubit restarts', () async {
    final directory = await Directory.systemTemp.createTemp(
      'form-preferences-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/preferences.sqlite');
    final database = AppDatabase(NativeDatabase(file));
    final repository = PreferencesRepository(database);
    expect(await repository.language(), isNull);
    final cubit = LanguageCubit(repository, 'de');
    await cubit.select('en');
    expect(cubit.state, 'en');
    await cubit.close();
    await database.close();

    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final restored = PreferencesRepository(reopened);
    expect(await restored.language(), 'en');
    final next = LanguageCubit(restored, (await restored.language())!);
    addTearDown(next.close);
    await next.select('de');
    expect(next.state, 'de');
    expect(await restored.language(), 'de');
  });

  test(
    'unsupported saved languages fall back and cannot be selected',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = PreferencesRepository(database);
      await database.setPreference('language', 'fr');
      expect(await repository.language(), isNull);
      final cubit = LanguageCubit(repository, 'de');
      addTearDown(cubit.close);
      await expectLater(cubit.select('fr'), throwsArgumentError);
      expect(cubit.state, 'de');
    },
  );
}
