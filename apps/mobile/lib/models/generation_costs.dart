/// Weekly response from the generation-costs contract. Keep microunits intact
/// until presentation so rounding never changes the total or its shares.
class GenerationCosts {
  const GenerationCosts({
    required this.lookTotalMicrounits,
    required this.successfulLookCount,
    required this.averageSuccessfulLookMicrounits,
    required this.characterSheetTotalMicrounits,
    required this.wardrobeTotalMicrounits,
    required this.wardrobeRequestCount,
    required this.detectionTotalMicrounits,
    required this.detectionRequestCount,
  });

  factory GenerationCosts.fromJson(Map<String, dynamic> json) {
    int read(String key) {
      final value = json[key];
      if (value is! num ||
          !value.isFinite ||
          value < 0 ||
          value != value.truncateToDouble()) {
        throw FormatException('Invalid generation cost field: $key');
      }
      return value.toInt();
    }

    return GenerationCosts(
      lookTotalMicrounits: read('lookTotalMicrounits'),
      successfulLookCount: read('successfulLookCount'),
      averageSuccessfulLookMicrounits: read('averageSuccessfulLookMicrounits'),
      characterSheetTotalMicrounits: read('characterSheetTotalMicrounits'),
      wardrobeTotalMicrounits: read('wardrobeTotalMicrounits'),
      wardrobeRequestCount: read('wardrobeRequestCount'),
      detectionTotalMicrounits: read('detectionTotalMicrounits'),
      detectionRequestCount: read('detectionRequestCount'),
    );
  }

  final int lookTotalMicrounits;
  final int successfulLookCount;
  final int averageSuccessfulLookMicrounits;
  final int characterSheetTotalMicrounits;
  final int wardrobeTotalMicrounits;
  final int wardrobeRequestCount;
  final int detectionTotalMicrounits;
  final int detectionRequestCount;
}
