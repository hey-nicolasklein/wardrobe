import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
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

  test('higherQualities offers only upgrades', () {
    expect(higherQualities('low'), ['medium', 'high']);
    expect(higherQualities('medium'), ['high']);
    expect(higherQualities('high'), isEmpty);
  });
}
