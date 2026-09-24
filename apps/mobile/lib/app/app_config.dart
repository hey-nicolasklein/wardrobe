import 'package:flutter/services.dart';

class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.flavor});

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment('FORM_API_BASE_URL'),
    flavor: appFlavor ?? 'development',
  );

  final String apiBaseUrl;
  final String flavor;

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
