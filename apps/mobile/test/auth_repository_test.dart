import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/repository/auth_repository.dart';
import 'package:form_mobile/services/form_api.dart';
import 'package:form_mobile/services/session_store.dart';

class AuthApi extends FormApi {
  AuthApi() : super(Dio());

  final calls = <(String, String, Map<String, dynamic>?)>[];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    calls.add((method, path, data));
    if (path == 'v1/auth/dev') {
      return {
        'session': {'nativeToken': 'token-' * 8},
      };
    }
    return const {};
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('dev sign-in stores the token and survives a restart', () async {
    final api = AuthApi();
    final repository = AuthRepository(api, SessionStore());
    await repository.signInForDevelopment('dev@form.local');

    expect(api.calls.single.$3, {
      'email': 'dev@form.local',
      'transport': 'token',
    });
    expect(repository.isSignedIn, isTrue);
    final restarted = SessionStore();
    await restarted.load();
    expect(restarted.token, 'token-' * 8);
  });

  test('deleting the account drops the local token', () async {
    final sessions = SessionStore();
    final repository = AuthRepository(AuthApi(), sessions);
    await repository.signInForDevelopment('dev@form.local');
    await repository.deleteAccount();

    expect(repository.isSignedIn, isFalse);
    await sessions.load();
    expect(sessions.token, isNull);
  });
}
