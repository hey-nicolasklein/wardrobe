import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/settings/reset_confirmation.dart';
import 'package:form_mobile/repository/personal_repository.dart';
import 'package:form_mobile/services/form_api.dart';

class PersonalApi extends FormApi {
  PersonalApi() : super(Dio());

  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    lastBody = data;
    return const {};
  }
}

void main() {
  test('reset sends the locale-independent confirmation value', () async {
    final api = PersonalApi();
    final repository = PersonalRepository(api);
    await repository.resetWardrobe();
    expect(api.lastBody?['confirmation'], personalResetApiConfirmation);
  });

  test('reset requires connectivity', () async {
    const repository = PersonalRepository(null);
    await expectLater(
      repository.resetWardrobe(),
      throwsA(isA<FormApiException>()),
    );
  });
}
