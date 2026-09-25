import 'package:form_mobile/features/settings/cost_week.dart';
import 'package:form_mobile/models/generation_costs.dart';
import 'package:form_mobile/services/form_api.dart';

class GenerationCostRepository {
  GenerationCostRepository(this.api);

  final FormApi? api;

  Future<GenerationCosts> fetch(CostWeek week) async {
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    final path = Uri(
      path: 'v1/generation-costs',
      queryParameters: {'week': week.value},
    );
    final response = await api!.request(path.toString());
    try {
      return GenerationCosts.fromJson(
        response['costs'] as Map<String, dynamic>,
      );
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
  }
}
