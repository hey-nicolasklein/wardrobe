import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/look_tile.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';

import 'support/look_fixtures.dart';
import 'support/wardrobe_fixtures.dart';

bool hasUnselectedProposalCore(List<CachedItem> records) =>
    proposalBlockKey(records) == null;

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

  test(
    'unselected proposals require an owned core with active catalog images',
    () {
      CachedItem piece(
        String category, {
        String state = 'owning',
        bool ready = true,
      }) {
        final json = itemJson(state: state);
        (json['metadata'] as Map<String, dynamic>)['category'] = category;
        if (!ready) json['currentShelfImageVersionId'] = null;
        return CachedItem(WardrobeItem.fromJson(json), null);
      }

      expect(hasUnselectedProposalCore([]), isFalse);
      expect(hasUnselectedProposalCore([piece('top')]), isFalse);
      expect(hasUnselectedProposalCore([piece('dress')]), isTrue);
      for (final bottom in ['pants', 'skirt']) {
        expect(
          hasUnselectedProposalCore([piece('top'), piece(bottom)]),
          isTrue,
        );
        expect(
          hasUnselectedProposalCore([
            piece('top'),
            piece(bottom, ready: false),
          ]),
          isFalse,
        );
        expect(
          hasUnselectedProposalCore([
            piece('top'),
            piece(bottom, state: 'wanting'),
          ]),
          isFalse,
        );
      }
      expect(
        hasUnselectedProposalCore([piece('dress', state: 'wanting')]),
        isFalse,
      );
      expect(
        hasUnselectedProposalCore([piece('dress', state: 'archived')]),
        isFalse,
      );
      expect(
        hasUnselectedProposalCore([piece('dress', ready: false)]),
        isFalse,
      );
    },
  );

  test(
    'explicit proposals validate every piece and category, including wishlist',
    () {
      final top = CachedItem(WardrobeItem.fromJson(itemJson(id: 'top')), null);
      final wishlist = CachedItem(
        WardrobeItem.fromJson(itemJson(id: 'wish', state: 'wanting')),
        null,
      );
      final pending = CachedItem(
        WardrobeItem.fromJson(
          itemJson(id: 'pending')..['currentShelfImageVersionId'] = null,
        ),
        null,
      );
      final archived = CachedItem(
        WardrobeItem.fromJson(itemJson(id: 'archived', state: 'archived')),
        null,
      );
      final records = [top, wishlist, pending, archived];
      expect(proposalBlockKey(records, selectedIds: ['wish']), isNull);
      expect(proposalBlockKey([wishlist], categories: ['top']), isNull);
      for (final id in ['pending', 'archived', 'deleted']) {
        expect(proposalBlockKey(records, selectedIds: ['top', id]), isNotNull);
      }
      expect(
        proposalBlockKey(records, selectedIds: ['top'], categories: ['dress']),
        isNotNull,
      );
      expect(
        proposalBlockKey(records, categories: ['top', 'dress']),
        isNotNull,
      );
      final pendingDressJson = itemJson(id: 'dress')
        ..['currentShelfImageVersionId'] = null;
      (pendingDressJson['metadata'] as Map<String, dynamic>)['category'] =
          'dress';
      expect(
        proposalBlockKey(
          [CachedItem(WardrobeItem.fromJson(pendingDressJson), null)],
          categories: ['dress'],
        ),
        isNotNull,
      );
    },
  );

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

  test('a card shows an AI image, try-ons first, else the flat lay', () {
    CachedLook record(Map<String, dynamic> json) =>
        CachedLook(Look.fromJson(json));
    String? cover(CachedLook look, List<CachedLook> looks) =>
        switch (lookCover(look, FeedState(looks: looks))) {
          PhotoCover(:final record) => record.look.id,
          FlatCover() => null,
        };
    final combination = record(
      lookJson(id: 'combination', kind: 'combination', assetId: null),
    );
    final inspiration = record(
      lookJson(id: 'inspiration', parentLookId: 'combination'),
    );
    final tryOn = record(
      lookJson(id: 'try-on', kind: 'try-on', parentLookId: 'combination'),
    );
    expect(cover(combination, [combination]), isNull);
    expect(cover(combination, [inspiration, combination]), 'inspiration');
    expect(cover(combination, [inspiration, tryOn, combination]), 'try-on');
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
      // A combination without an occasion is not a surprise look.
      final combination = Look.fromJson(lookJson(kind: 'combination'));
      expect(inStack(const OccasionStack(null), combination), isFalse);
      expect(
        inStack(const OccasionStack('party'), look(occasion: 'night-out')),
        isFalse,
      );
      expect(inStack(const SavedStack(), look(), saved: true), isTrue);
    });

    test('inspirations are AI scenes, not try-ons', () {
      expect(inStack(const InspirationStack(), look()), isTrue);
      expect(
        inStack(const InspirationStack(), look(baseAssetId: 'asset-1')),
        isFalse,
      );
      final combination = Look.fromJson(lookJson(kind: 'combination'));
      expect(inStack(const InspirationStack(), combination), isFalse);
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
