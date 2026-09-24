import 'package:form_mobile/services/app_database.dart';

/// Persists the language override and validates supported language codes.
class PreferencesRepository {
  const PreferencesRepository(this._database);

  final AppDatabase _database;

  Future<String?> language() async {
    final value = await _database.preference('language');
    return ['de', 'en'].contains(value) ? value : null;
  }

  Future<void> setLanguage(String language) {
    if (!['de', 'en'].contains(language)) {
      throw ArgumentError.value(language, 'language');
    }
    return _database.setPreference('language', language);
  }
}
