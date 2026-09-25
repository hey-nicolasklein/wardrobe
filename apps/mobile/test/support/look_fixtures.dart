import 'package:form_mobile/models/look.dart';

Map<String, dynamic> lookJson({
  String id = 'look-0001',
  String state = 'ready',
  List<String>? wardrobeItemIds,
  String? assetId = 'look-asset-0001',
  String quality = 'low',
}) {
  final ids = wardrobeItemIds ?? ['wardrobe-item-0001'];
  return {
    'id': id,
    'state': state,
    'assetId': assetId,
    'wardrobeItemIds': ids,
    'characterSheetId': 'character-sheet-0001',
    'parentLookId': null,
    'concept': {
      'activity': 'Evening walk',
      'scene': 'City lights',
      'framing': 'full-body',
      'mood': 'Relaxed',
    },
    'model': 'test-model',
    'quality': quality,
    'size': '1024x1280',
    'providerRequestId': null,
    'costMicrounits': 1200,
    'failureCategory': null,
    'createdAt': '2026-09-10T12:00:00.000Z',
    'finishedAt': state == 'ready' ? '2026-09-10T12:05:00.000Z' : null,
  };
}

Look readyLook({String id = 'look-0001', List<String>? itemIds}) =>
    Look.fromJson(lookJson(id: id, wardrobeItemIds: itemIds));
