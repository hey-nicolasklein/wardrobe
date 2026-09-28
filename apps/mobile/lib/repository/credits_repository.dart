import 'package:form_mobile/services/form_api.dart';

/// Credit costs per generation. Mirrors `jobCreditCost` in
/// packages/service/src/credits.ts.
const lookCreditCost = 2;
const shelfImageCreditCost = 1;

class Credits {
  const Credits({required this.metered, required this.balance});

  factory Credits.fromJson(Map<String, dynamic> json) => Credits(
    metered: json['metered'] as bool,
    balance: json['balance'] as int,
  );

  /// Unmetered accounts generate without a budget.
  final bool metered;
  final int balance;

  int get looksLeft => balance < 0 ? 0 : balance ~/ lookCreditCost;
  int get shelfImagesLeft => balance < 0 ? 0 : balance ~/ shelfImageCreditCost;
}

class CreditsRepository {
  CreditsRepository(this.api);

  final FormApi? api;

  Future<Credits> fetch() async {
    if (api == null) throw const FormApiException(ApiFailure.unavailable);
    final response = await api!.request('v1/credits');
    try {
      return Credits.fromJson(response);
    } on Object {
      throw const FormApiException(ApiFailure.incompatible);
    }
  }
}
