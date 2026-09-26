import 'package:flutter/services.dart';

class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.flavor,
    this.googleClientId = '',
    this.googleServerClientId = '',
    this.appleSignIn = false,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment('FORM_API_BASE_URL'),
    flavor: appFlavor ?? 'development',
    googleClientId: String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    googleServerClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    appleSignIn: bool.fromEnvironment('APPLE_SIGN_IN'),
  );

  final String apiBaseUrl;
  final String flavor;

  /// Google OAuth client IDs. Empty hides Google sign-in.
  final String googleClientId;
  final String googleServerClientId;

  /// Needs the Sign in with Apple capability, which requires a paid Apple
  /// developer account. Off hides Apple sign-in.
  final bool appleSignIn;

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
