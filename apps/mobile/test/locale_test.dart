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

  test('both shell languages have the same complete keys', () {
    Map<String, dynamic> translations(String language) =>
        jsonDecode(
              File('assets/translations/$language.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final de = translations('de');
    final en = translations('en');
    expect(de.keys.toSet(), en.keys.toSet());
    expect(
      [
        ...de.values,
        ...en.values,
      ].every((dynamic value) => value is String && value.isNotEmpty),
      isTrue,
    );
  });
}
