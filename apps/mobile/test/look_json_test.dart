import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_json.dart';

const _lookId = '80000000-0000-4000-8000-000000000001';
const _itemId = '40000000-0000-4000-8000-000000000001';
const _sheetId = '90000000-0000-4000-8000-000000000001';
const _assetId = '20000000-0000-4000-8000-000000000003';

Map<String, dynamic> contractLookJson() => {
  'id': _lookId,
  'state': 'ready',
  'assetId': _assetId,
  'wardrobeItemIds': [_itemId],
  'characterSheetId': _sheetId,
  'parentLookId': null,
  'concept': {
    'activity': 'Evening walk',
    'scene': 'City lights',
    'framing': 'full-body',
    'mood': 'Relaxed',
  },
  'model': 'test-model',
  'quality': 'low',
  'size': '1024x1280',
  'providerRequestId': null,
  'costMicrounits': 1200,
  'failureCategory': null,
  'createdAt': '2026-09-10T12:00:00.000Z',
  'finishedAt': '2026-09-10T12:05:00.000Z',
};

void main() {
  test('normalizeLookJson accepts contract payloads', () {
    final json = contractLookJson();
    expect(Look.fromJson(normalizeLookJson(json)).id, _lookId);
  });

  test('normalizeLookJson maps snake_case and coerces cost', () {
    final json = {
      'id': _lookId,
      'state': 'ready',
      'asset_id': _assetId,
      'wardrobe_item_ids': [_itemId],
      'item_bounding_boxes': [
        {
          'wardrobe_item_id': _itemId,
          'bounding_box': {'x': '320', 'y': 240, 'width': 360, 'height': 400},
        },
      ],
      'character_sheet_id': _sheetId,
      'parent_look_id': '',
      'concept': null,
      'model': 'test-model',
      'quality': 'low',
      'size': '1024x1280',
      'provider_request_id': '',
      'cost_microunits': '500',
      'failure_category': '',
      'created_at': '2026-09-10T12:00:00.000Z',
      'finished_at': '2026-09-10T12:05:00.000Z',
    };
    final look = Look.fromJson(normalizeLookJson(json));
    expect(look.costMicrounits, 500);
    expect(look.parentLookId, isNull);
  });

  test('normalizeLookJson drops invalid concepts', () {
    final json = {
      ...contractLookJson(),
      'concept': {
        'activity': 'a',
        'scene': 'b',
        'framing': 'portrait',
        'mood': 'c',
      },
    };
    expect(Look.fromJson(normalizeLookJson(json)).concept, isNull);
  });
}
