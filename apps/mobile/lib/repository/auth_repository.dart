import 'dart:io';

import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/services/session_store.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Thrown when the user closes the Apple or Google sheet. Not an error to show.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// Signs in through Apple, Google, or the dev shortcut and keeps the resulting
/// session token in [SessionStore].
class AuthRepository {
  AuthRepository(
    this._api,
    this._sessions, {
    this.googleClientId,
    this.googleServerClientId,
  });

  final FormApi? _api;
  final SessionStore _sessions;

  /// iOS OAuth client ID. Android reads its client from google-services.
  final String? googleClientId;

  /// Web OAuth client ID. Google issues Android ID tokens for this audience.
  final String? googleServerClientId;

  bool _googleReady = false;

  bool get isSignedIn => _sessions.token != null;

  /// iOS needs its own client ID (plus the reversed-ID URL scheme in
  /// Info.plist), Android only the server client ID.
  bool get googleAvailable => (Platform.isIOS
          ? googleClientId ?? ''
          : googleServerClientId ?? '')
      .isNotEmpty;

  Future<void> signInWithApple() async {
    final String? idToken;
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
      );
      idToken = credential.identityToken;
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const SignInCancelled();
      }
      rethrow;
    }
    if (idToken == null) throw const FormApiException(ApiFailure.rejected);
    await _exchange('v1/auth/apple', {'idToken': idToken});
  }

  Future<void> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(
        clientId: googleClientId,
        serverClientId: googleServerClientId,
      );
      _googleReady = true;
    }
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const SignInCancelled();
      }
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw const FormApiException(ApiFailure.rejected);
    await _exchange('v1/auth/google', {'idToken': idToken});
  }

  /// Password-free sign-in against an API started with DEV_SIGN_IN=true.
  Future<void> signInForDevelopment(String email) =>
      _exchange('v1/auth/dev', {'email': email});

  Future<void> signOut() async {
    try {
      await _api?.request('v1/auth/sign-out', method: 'POST');
    } on FormApiException {
      // The local token is dropped either way.
    }
    await _sessions.clear();
  }

  /// Permanently deletes the account and every record on the server.
  Future<void> deleteAccount() async {
    final api = _api;
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    await api.request('v1/account', method: 'DELETE');
    await _sessions.clear();
  }

  Future<void> _exchange(String path, Map<String, dynamic> body) async {
    final api = _api;
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    final data = await api.request(
      path,
      method: 'POST',
      data: {...body, 'transport': 'token'},
    );
    final session = data['session'];
    final token = session is Map<String, dynamic>
        ? session['nativeToken']
        : null;
    if (token is! String) throw const FormApiException(ApiFailure.incompatible);
    await _sessions.save(token);
  }
}
