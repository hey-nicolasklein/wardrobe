import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/app/app_config.dart';

void main() {
  test(
    'base URL preserves the API prefix and normalizes the trailing slash',
    () {
      expect(
        const AppConfig(
          apiBaseUrl: 'https://example.test/api',
          flavor: 'production',
        ).apiUri.toString(),
        'https://example.test/api/',
      );
      expect(
        const AppConfig(
          apiBaseUrl: 'http://localhost:4143',
          flavor: 'development',
        ).apiUri.toString(),
        'http://localhost:4143/',
      );
    },
  );

  test('unknown flavors are rejected', () {
    expect(
      const AppConfig(
        apiBaseUrl: 'https://example.test',
        flavor: 'staging',
      ).apiUri,
      isNull,
    );
  });

  test('invalid URLs and insecure production URLs cannot reach the API', () {
    for (final url in [
      '',
      '/relative',
      'ftp://example.test',
      'https://user:pass@example.test',
      'https://example.test?token=secret',
      'https://example.test#fragment',
      'http://example.test',
    ]) {
      expect(AppConfig(apiBaseUrl: url, flavor: 'production').apiUri, isNull);
    }
  });

  test('dev sign-in needs the flag and both credentials', () {
    const base = AppConfig(apiBaseUrl: '', flavor: 'development');
    expect(base.devSignIn, isFalse);
    expect(
      const AppConfig(
        apiBaseUrl: '',
        flavor: 'development',
        devMode: true,
        devEmail: 'nico@example.test',
      ).devSignIn,
      isFalse,
    );
    expect(
      const AppConfig(
        apiBaseUrl: '',
        flavor: 'development',
        devMode: true,
        devEmail: 'nico@example.test',
        devPassword: 'secret',
      ).devSignIn,
      isTrue,
    );
  });
}
