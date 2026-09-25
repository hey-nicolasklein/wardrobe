import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:form_mobile/models/generation_costs.dart';

String costMoney(int microunits, String locale) => NumberFormat.currency(
  locale: locale,
  name: 'USD',
  decimalDigits: 2,
).format(microunits / 1000000);

enum CostSource { looks, wardrobe, detection }

class CostPart {
  const CostPart({
    required this.source,
    required this.microunits,
    required this.count,
    required this.share,
  });

  final CostSource source;
  final int microunits;
  final int count;
  final int? share;
}

class CostDisplay {
  CostDisplay(GenerationCosts costs) {
    final values = [
      math.max(costs.lookTotalMicrounits, 0),
      math.max(costs.wardrobeTotalMicrounits, 0),
      math.max(costs.detectionTotalMicrounits, 0),
    ];
    final counts = [
      costs.successfulLookCount,
      costs.wardrobeRequestCount,
      costs.detectionRequestCount,
    ];
    totalMicrounits = values.fold(0, (sum, value) => sum + value);
    final lastVisible = values.lastIndexWhere((value) => value > 0);
    var remaining = 100;
    final result = <CostPart>[];
    for (var index = 0; index < values.length; index++) {
      final share = totalMicrounits == 0
          ? null
          : index == lastVisible
          ? remaining
          : (values[index] / totalMicrounits * 100).round();
      if (share != null) remaining -= share;
      result.add(
        CostPart(
          source: CostSource.values[index],
          microunits: values[index],
          count: counts[index],
          share: share,
        ),
      );
    }
    parts = List.unmodifiable(result);
    averageMicrounits = costs.averageSuccessfulLookMicrounits;
  }

  // Character-reference costs remain in the DTO but are excluded by the
  // current PWA's three-source weekly presentation.
  late final int totalMicrounits;
  late final int averageMicrounits;
  late final List<CostPart> parts;
}
