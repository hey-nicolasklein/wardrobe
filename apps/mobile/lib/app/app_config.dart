// `fromEnvironment` values equal the defaults only when no define is passed.
// ignore_for_file: avoid_redundant_argument_values

import 'package:flutter/services.dart';

class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.flavor,
    this.googleClientId = '',
    this.googleServerClientId = '',
    this.appleSignIn = false,
    this.devMode = false,
    this.devEmail = '',
    this.devPassword = '',
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment('FORM_API_BASE_URL'),
    flavor: appFlavor ?? 'development',
    googleClientId: String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    googleServerClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    appleSignIn: bool.fromEnvironment('APPLE_SIGN_IN'),
    devMode: bool.fromEnvironment('DEV_MODE'),
    devEmail: String.fromEnvironment('DEV_EMAIL'),
    devPassword: String.fromEnvironment('DEV_PASSWORD'),
  );

  final String apiBaseUrl;
  final String flavor;

  /// Google OAuth client IDs. Empty hides Google sign-in.
  final String googleClientId;
  final String googleServerClientId;

  /// Needs the Sign in with Apple capability, which requires a paid Apple
  /// developer account. Off hides Apple sign-in.
  final bool appleSignIn;

  /// Adds a one-tap sign-in with [devEmail] and [devPassword] to the sign-in
  /// page. The credentials are compiled into the app, so only set them in
  /// ignored local env files.
  final bool devMode;
  final String devEmail;
  final String devPassword;

  bool get devSignIn =>
      devMode && devEmail.isNotEmpty && devPassword.isNotEmpty;

  Uri? get apiUri {
    final uri = Uri.tryParse(apiBaseUrl);
    if (!['development', 'production'].contains(flavor) ||
        uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['https', 'http'].contains(uri.scheme) ||
        (flavor == 'production' && uri.scheme != 'https')) {
      return null;
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }
}
