import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';

import 'support/look_fixtures.dart';
import 'support/wardrobe_fixtures.dart';

void main() {
  test('lookGarments prefers server ids and falls back to pending starts', () {
    final look = Look.fromJson(
      lookJson(state: 'planning', assetId: null, wardrobeItemIds: []),
    );
    final item = WardrobeItem.fromJson(itemJson());
    final byId = {item.id: item};
    expect(
      lookGarments(look, byId, pendingItemIds: [item.id]).single.item,
      item,
    );
    expect(lookGarments(look, byId), isEmpty);
  });

  test('lookAgeDays counts local calendar days, never negative', () {
    final now = DateTime(2026, 9, 10, 0, 30);
    expect(lookAgeDays(DateTime(2026, 9, 10, 0, 5), now: now), 0);
    expect(lookAgeDays(DateTime(2026, 9, 9, 23, 55), now: now), 1);
    expect(lookAgeDays(DateTime(2026, 9, 3, 12), now: now), 7);
    expect(lookAgeDays(DateTime(2026, 9, 11, 12), now: now), 0);
  });

  test('composer eligibility and ready looks for item', () {
    final owning = CachedItem(WardrobeItem.fromJson(itemJson()), null);
    final archived = CachedItem(
      WardrobeItem.fromJson(
        itemJson(id: 'wardrobe-item-0002', state: 'archived'),
      ),
      null,
    );
    final noShelf = CachedItem(
      WardrobeItem.fromJson(
        itemJson(id: 'wardrobe-item-0003')
          ..['currentShelfImageVersionId'] = null,
      ),
      null,
    );
    expect(
      eligibleComposerItems([owning, archived, noShelf]).map((i) => i.id),
      [owning.item.id],
    );
    final ready = Look.fromJson(lookJson());
    final other = Look.fromJson(
      lookJson(id: 'look-0002', wardrobeItemIds: ['wardrobe-item-0002']),
    );
    expect(
      readyLooksForItem('wardrobe-item-0001', [ready, other]).single.id,
      ready.id,
    );
  });

  test('images of a combination stay with it, other looks stand alone', () {
    CachedLook record(Map<String, dynamic> json) =>
        CachedLook(Look.fromJson(json));
    final combination = record(
      lookJson(id: 'combination', kind: 'combination', assetId: null),
    );
    final developing = record(
      lookJson(
        id: 'developing',
        kind: 'try-on',
        state: 'generating',
        assetId: null,
        parentLookId: 'combination',
      ),
    );
    final ready = record(
      lookJson(id: 'ready', parentLookId: 'combination'),
    );
    // A variation of a generated look is a look of its own, as before.
    final legacy = record(lookJson(id: 'legacy'));
    final variation = record(lookJson(id: 'variation', parentLookId: 'legacy'));
    final state = FeedState(
      looks: [developing, ready, combination, legacy, variation],
    );
    expect(state.archive.map((r) => r.look.id), [
      'combination',
      'legacy',
      'variation',
    ]);
    expect(state.imagesOf('combination').map((r) => r.look.id), [
      'developing',
      'ready',
    ]);
    // The newest finished image covers the combination on its print.
    expect(state.coverOf(combination)?.look.id, 'ready');
    expect(state.coverOf(legacy)?.look.id, 'legacy');
  });

  test('higherQualities offers only upgrades', () {
    expect(higherQualities('low'), ['medium', 'high']);
    expect(higherQualities('medium'), ['high']);
    expect(higherQualities('high'), isEmpty);
  });

  group('look stacks', () {
    Look look({
      String id = 'look-0001',
      String? occasion,
      String? baseAssetId,
      List<String> items = const [],
    }) => Look.fromJson({
      ...lookJson(id: id),
      'wardrobeItemIds': items,
      'settings': {
        'occasion': occasion,
        'style': 'candid',
        'completion': 'wardrobe',
        'categories': <String>[],
      },
      'baseAssetId': baseAssetId,
    });
    final white = WardrobeItem.fromJson({
      ...itemJson(id: 'white'),
      'metadata': {
        ...itemJson()['metadata'] as Map<String, dynamic>,
        'colors': ['Off-White'],
      },
    });
    final red = WardrobeItem.fromJson({
      ...itemJson(id: 'red'),
      'metadata': {
        ...itemJson()['metadata'] as Map<String, dynamic>,
        'colors': ['bordeaux'],
      },
    });
    final byId = {white.id: white, red.id: red};

    bool inStack(LookStack stack, Look look, {bool saved = false}) =>
        inLookStack(stack, look, itemsById: byId, saved: saved);

    test('occasion stacks keep try-ons apart', () {
      expect(inStack(const OccasionStack(null), look()), isTrue);
      final tryOn = look(baseAssetId: 'asset-1');
      expect(inStack(const OccasionStack(null), tryOn), isFalse);
      expect(inStack(const TryOnStack(), tryOn), isTrue);
      // A photo look has no settings and is not a surprise look.
      final photo = Look.fromJson({...lookJson(kind: 'photo')});
      expect(inStack(const OccasionStack(null), photo), isFalse);
      expect(inStack(const PhotoStack(), photo), isTrue);
      expect(
        inStack(const OccasionStack('party'), look(occasion: 'night-out')),
        isFalse,
      );
      expect(inStack(const SavedStack(), look(), saved: true), isTrue);
    });

    test('pieces and colours gather the looks they appear in', () {
      final looks = [
        CachedLook(look(id: 'a', items: ['red'])),
        CachedLook(look(id: 'b', items: ['white', 'red'])),
        CachedLook(look(id: 'c', items: ['white'])),
        CachedLook(look(id: 'd', items: ['white'])),
      ];
      expect(inStack(const ColorStack('white'), looks[1].look), isTrue);
      expect(inStack(const PieceStack('red'), looks[2].look), isFalse);

      final pieces = pieceStacks(looks, byId);
      expect(pieces.map((s) => s.$1.id), ['white', 'red']);
      expect(pieces.first.$2.map((r) => r.look.id), ['b', 'c', 'd']);

      final colors = colorStacks(looks, byId);
      expect(colors.map((s) => s.$1), ['white', 'red']);
    });
  });
}
