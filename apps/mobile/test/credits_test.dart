import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/repository/credits_repository.dart';
import 'package:form_mobile/services/form_api.dart';

class CreditsApi extends FormApi {
  CreditsApi() : super(Dio());
  Map<String, dynamic> Function() respond = () => {
    'metered': true,
    'balance': 7,
  };
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async => respond();
}

void main() {
  test('the balance translates into looks and catalog images left', () {
    const credits = Credits(metered: true, balance: 7);
    expect(credits.looksLeft, 3);
    expect(credits.shelfImagesLeft, 7);
    expect(const Credits(metered: true, balance: -1).looksLeft, 0);
  });

  test(
    'a failed refresh keeps the last balance and sign-out clears it',
    () async {
      final api = CreditsApi();
      final cubit = CreditsCubit(CreditsRepository(api));
      await cubit.refresh();
      expect(cubit.state?.balance, 7);

      api.respond = () => throw const FormApiException(ApiFailure.unavailable);
      await cubit.refresh();
      expect(cubit.state?.balance, 7);

      api.respond = () => {'metered': 'yes'};
      await cubit.refresh();
      expect(cubit.state?.balance, 7);

      cubit.clear();
      expect(cubit.state, isNull);
      await cubit.close();
    },
  );
}
