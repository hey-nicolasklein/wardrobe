import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_json.dart';

import 'support/look_fixtures.dart';

void main() {
  test('looks at the current 768x960 size parse', () {
    final json = lookJson()..['size'] = '768x960';
    expect(Look.fromJson(normalizeLookJson(json)).size, '768x960');
  });

  test('strict look DTOs round trip and reject invalid payloads', () {
    expect(Look.fromJson(lookJson()).toJson(), lookJson());
    for (final patch in [
      {'state': 'unknown'},
      {'size': '512x512'},
      {'quality': 'ultra'},
      {'id': ''},
      {'kind': 'collage'},
    ]) {
      expect(
        () => Look.fromJson({...lookJson(), ...patch}),
        throwsA(isA<Exception>()),
      );
    }
    expect(
      () => LookConcept.fromJson({
        'activity': 'a',
        'scene': 'b',
        'framing': 'portrait',
        'mood': 'c',
      }),
      throwsFormatException,
    );
  });

  test('looks cached before kinds existed read as generated looks', () {
    final legacy = lookJson()..remove('kind');
    expect(Look.fromJson(normalizeLookJson(legacy)).kind, 'inspiration');
    final tryOn = {...legacy, 'baseAssetId': 'photo-0001'};
    expect(Look.fromJson(normalizeLookJson(tryOn)).kind, 'try-on');
  });

  test('photo looks from before their removal read as combinations', () {
    final json = lookJson(kind: 'photo')..['assetId'] = 'photo-0001';
    final look = Look.fromJson(normalizeLookJson(json));
    expect(look.kind, 'combination');
    expect(look.assetId, isNull);
  });

  test('character sheet validation matches contract', () {
    final json = {
      'id': 'character-sheet-0001',
      'state': 'ready',
      'referenceAssetIds': ['ref-1'],
      'note': null,
      'assetId': 'char-asset-1',
      'active': true,
      'model': 'test-model',
      'quality': 'high',
      'size': '864x1536',
      'providerRequestId': null,
      'costMicrounits': null,
      'failureCategory': null,
      'createdAt': '2026-09-01T10:00:00.000Z',
      'finishedAt': '2026-09-02T10:00:00.000Z',
    };
    expect(CharacterSheet.fromJson(json).toJson(), json);
    expect(
      () => CharacterSheet.fromJson({...json, 'quality': 'low'}),
      throwsFormatException,
    );
  });
}
