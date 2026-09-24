import 'package:form_mobile/services/form_api.dart';

class ServerRepository {
  const ServerRepository(this._api);

  final FormApi _api;

  Future<void> checkAccess() async {
    final info = await _api.serverInfo();
    if (!info.isCompatible) {
      throw const FormApiException(ApiFailure.incompatible);
    }
    await _api.session();
  }
}
