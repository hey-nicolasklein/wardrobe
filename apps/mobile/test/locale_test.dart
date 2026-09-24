import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/utils/initial_language.dart';

void main() {
  test(
    'device language initializes once with German fallback and saved override',
    () {
      expect(initialLanguage(deviceLanguage: 'en'), 'en');
      expect(initialLanguage(deviceLanguage: 'de'), 'de');
      expect(initialLanguage(deviceLanguage: 'fr'), 'de');
      expect(initialLanguage(deviceLanguage: 'de', savedLanguage: 'en'), 'en');
      expect(initialLanguage(deviceLanguage: 'en', savedLanguage: 'de'), 'de');
      expect(initialLanguage(deviceLanguage: 'en', savedLanguage: 'fr'), 'en');
    },
  );

  test('both languages have the same complete leaf keys', () {
    Map<String, dynamic> translations(String language) =>
        jsonDecode(
              File('assets/translations/$language.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    Map<String, String> flatten(
      Map<String, dynamic> values, [
      String prefix = '',
    ]) {
      final result = <String, String>{};
      for (final entry in values.entries) {
        final key = '$prefix${entry.key}';
        if (entry.value is Map<String, dynamic>) {
          result.addAll(flatten(entry.value as Map<String, dynamic>, '$key.'));
        } else {
          expect(entry.value, isA<String>());
          result[key] = entry.value as String;
        }
      }
      return result;
    }

    final de = flatten(translations('de'));
    final en = flatten(translations('en'));
    expect(de.keys.toSet(), en.keys.toSet());
    expect(
      [...de.values, ...en.values].every((value) => value.isNotEmpty),
      isTrue,
    );
  });
}
