/// Normalizes look payloads from cache or API before strict DTO parsing.
Map<String, dynamic> normalizeLookJson(Map<String, dynamic> json) {
  final normalized = Map<String, dynamic>.from(json);
  for (final (camel, snake) in [
    ('wardrobeItemIds', 'wardrobe_item_ids'),
    ('characterSheetId', 'character_sheet_id'),
    ('parentLookId', 'parent_look_id'),
    ('assetId', 'asset_id'),
    ('providerRequestId', 'provider_request_id'),
    ('costMicrounits', 'cost_microunits'),
    ('failureCategory', 'failure_category'),
    ('createdAt', 'created_at'),
    ('finishedAt', 'finished_at'),
  ]) {
    if (!normalized.containsKey(camel) && normalized.containsKey(snake)) {
      normalized[camel] = normalized[snake];
    }
  }
  normalized
    ..putIfAbsent('wardrobeItemIds', () => <String>[])
    ..putIfAbsent('concept', () => null)
    ..putIfAbsent('parentLookId', () => null)
    ..putIfAbsent('assetId', () => null)
    ..putIfAbsent('providerRequestId', () => null)
    ..putIfAbsent('costMicrounits', () => null)
    ..putIfAbsent('failureCategory', () => null)
    ..putIfAbsent('finishedAt', () => null);
  final cost = normalized['costMicrounits'];
  if (cost is String) {
    normalized['costMicrounits'] = int.tryParse(cost);
  } else if (cost is num) {
    normalized['costMicrounits'] = cost.toInt();
  }
  for (final key in [
    'assetId',
    'parentLookId',
    'providerRequestId',
    'failureCategory',
    'finishedAt',
  ]) {
    final value = normalized[key];
    if (value is String && value.isEmpty) {
      normalized[key] = null;
    }
  }
  final concept = normalized['concept'];
  if (concept is Map<String, dynamic>) {
    final activity = concept['activity'];
    final scene = concept['scene'];
    final mood = concept['mood'];
    final framing = concept['framing'];
    if (activity is! String ||
        activity.isEmpty ||
        scene is! String ||
        scene.isEmpty ||
        mood is! String ||
        mood.isEmpty ||
        framing is! String ||
        !['full-body', 'three-quarter'].contains(framing)) {
      normalized['concept'] = null;
    }
  } else if (concept != null) {
    normalized['concept'] = null;
  }
  return normalized;
}
