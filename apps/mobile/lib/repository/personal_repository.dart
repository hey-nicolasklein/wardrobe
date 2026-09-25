import 'package:form_mobile/features/settings/reset_confirmation.dart';
import 'package:form_mobile/services/form_api.dart';

class PersonalRepository {
  const PersonalRepository(this.api);

  final FormApi? api;

  Future<void> resetWardrobe() async {
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    await api!.request(
      'v1/personal/reset',
      method: 'POST',
      data: {'confirmation': personalResetApiConfirmation},
    );
  }
}
