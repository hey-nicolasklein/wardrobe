import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/services/app_database.dart';

/// Persists app preferences that survive account resets.
class PreferencesRepository {
  const PreferencesRepository(this._database);

  final AppDatabase _database;

  static const feedQualityKey = 'feed-quality';
  static const wardrobeQualityKey = 'wardrobe-quality';
  static const onboardingKey = 'onboarding-seen';

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

  /// An account reset clears this, so an emptied account starts with
  /// onboarding again.
  Future<bool> onboardingSeen() async =>
      await _database.preference(onboardingKey) == 'true';

  Future<void> setOnboardingSeen() =>
      _database.setPreference(onboardingKey, 'true');

  Future<String> feedQuality() => _quality(feedQualityKey);

  Future<String> wardrobeQuality() => _quality(wardrobeQualityKey);

  Future<void> setFeedQuality(String quality) =>
      _setQuality(feedQualityKey, quality);

  Future<void> setWardrobeQuality(String quality) =>
      _setQuality(wardrobeQualityKey, quality);

  Future<String> _quality(String key) async {
    final value = await _database.preference(key);
    return qualities.contains(value) ? value! : 'low';
  }

  Future<void> _setQuality(String key, String quality) {
    if (!qualities.contains(quality)) {
      throw ArgumentError.value(quality, 'quality');
    }
    return _database.setPreference(key, quality);
  }
}
