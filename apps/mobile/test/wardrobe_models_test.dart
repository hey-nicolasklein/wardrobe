import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/wardrobe/item_edit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/services/app_database.dart';

import 'support/wardrobe_fixtures.dart';

void main() {
  test('DTO collections and nested command payloads are immutable', () {
    final detail = ItemDetail.fromJson(detailJson());
    expect(detail.shelfImageVersions.clear, throwsUnsupportedError);
    expect(detail.wardrobeItem.metadata.colors.clear, throwsUnsupportedError);
    final command = ItemCommand.edit(detail.wardrobeItem, {
      'metadata': detail.wardrobeItem.metadata.toJson(),
    });
    expect(
      () => (command.body['metadata'] as Map<String, dynamic>).clear(),
      throwsUnsupportedError,
    );
  });
  test('edit validation and normalization match the contract', () {
    final edit = ItemEdit(
      name: ' Shirt ',
      category: 'top',
      colors: ' navy, white ',
      notes: ' ',
      state: 'owning',
    );
    expect(edit.metadata.name, 'Shirt');
    expect(edit.metadata.colors, ['navy', 'white']);
    expect(edit.metadata.notes, isNull);
    expect(ItemEdit.validColors('blue,,red'), isFalse);
    expect(
      () => ItemEdit(
        name: '',
        category: 'top',
        colors: 'blue',
        notes: '',
        state: 'owning',
      ),
      throwsFormatException,
    );
  });
  test('strict DTOs round trip baseline item and complete detail', () {
    expect(WardrobeItem.fromJson(itemJson()).toJson(), itemJson());
    expect(ItemDetail.fromJson(detailJson()).toJson(), detailJson());
    for (final field in itemJson().keys) {
      expect(
        () => WardrobeItem.fromJson(itemJson()..remove(field)),
        throwsA(isA<Exception>()),
      );
    }
    for (final patch in [
      {'recordVersion': -1},
      {'recordVersion': '3'},
      {'state': 'unknown'},
      {'status': 'unknown'},
      {'createdAt': 'not-a-date'},
    ]) {
      expect(
        () => WardrobeItem.fromJson({...itemJson(), ...patch}),
        throwsA(isA<Exception>()),
      );
    }
    expect(
      () => ItemMetadata.fromJson({
        'name': '',
        'category': 'unsupported',
        'colors': <String>[],
        'notes': null,
      }),
      throwsFormatException,
    );
    expect(
      () => ItemDetail.fromJson(detailJson()..remove('sourcePhoto')),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'cache mapping preserves version, detail and immutable media identity',
    () {
      final record = CachedItem.fromRecord(
        WardrobeRecord(
          scope: 'server',
          id: 'wardrobe-item-0001',
          itemJson: jsonEncode(itemJson(version: 4)),
          detailJson: jsonEncode(detailJson()),
        ),
      );
      expect(record.item.recordVersion, 4);
      expect(record.detail!.wardrobeItem.recordVersion, 3);
      expect(
        record.detail!.currentImage!.transparentAssetId,
        'transparent-0001',
      );
      expect(record.thumbnailIdentity, 'preview:wardrobe-item-0001:4');
    },
  );

  test(
    'color families exactly include multiple matches and unknown fallback',
    () {
      expect(colorFamilies(' Weiß / Navy '), {'white', 'blue'});
      expect(colorFamilies('anthrazit'), {'black'});
      expect(colorFamilies('türkis'), {'blue'});
      expect(colorFamilies('salbei'), {'green'});
      expect(colorFamilies('unknown'), {'other'});
      expect(colorFamilies('multicolor rot'), {'red', 'other'});
    },
  );

  test(
    'filters combine, reset, search localized labels and sort by creation',
    () {
      final first = CachedItem(WardrobeItem.fromJson(itemJson()), null);
      final second = CachedItem(
        WardrobeItem.fromJson(
          itemJson(id: 'wardrobe-item-0002', state: 'wanting')
            ..['createdAt'] = '2026-09-03T10:00:00.000Z',
        ),
        null,
      );
      final archived = CachedItem(
        WardrobeItem.fromJson(
          itemJson(id: 'wardrobe-item-0003', state: 'archived'),
        ),
        null,
      );
      final records = [first, second, archived];
      const labels = {'top': 'Oberteil'};
      List<CachedItem> apply(WardrobeFilter filter) =>
          filter.apply(records, archived: false, categoryLabels: labels);
      expect(apply(const WardrobeFilter()), [second, first]);
      for (final query in ['LINEN', 'navy', 'summer', 'oberteil']) {
        expect(apply(WardrobeFilter(query: query)), [second, first]);
      }
      const filter = WardrobeFilter(
        state: 'wanting',
        categories: {'top'},
        colors: {'blue'},
        query: 'linen',
      );
      expect(apply(filter), [second]);
      expect(apply(filter.copyWith(colors: {'red'})), isEmpty);
      expect(apply(filter.copyWith(categories: {'shoes'})), isEmpty);
      expect(apply(filter.copyWith(state: 'owning')), [first]);
      expect(
        apply(
          filter.copyWith(categories: {}, colors: {}, query: '', state: 'all'),
        ),
        [second, first],
      );
      expect(
        const WardrobeFilter().apply(
          records,
          archived: true,
          categoryLabels: labels,
        ),
        [archived],
      );
    },
  );

  test('server generation states reduce to running or terminal', () {
    for (final state in [
      'queued',
      'processing',
      'needs-review',
      'kept',
      'rejected',
      'failed',
    ]) {
      final detail = ItemDetail.fromJson(detailJson(generation: state));
      expect(detail.generating, ['queued', 'processing'].contains(state));
    }
  });

  test('commands preserve record versions and one key per logical action', () {
    final item = WardrobeItem.fromJson(itemJson());
    for (final command in [
      ItemCommand.edit(item, {'state': 'archived'}),
      ItemCommand.delete(item),
      ItemCommand.restore(item, 'old-version'),
    ]) {
      expect(command.body['expectedRecordVersion'], 3);
      expect(command.body['idempotencyKey'], hasLength(48));
    }
    final command = ItemCommand.generate(item.id, 'high', 'Details');
    expect(command.body['autoKeep'], isTrue);
    expect(command.body['quality'], 'high');
    expect(command.body['feedback'], 'Details');
    expect(command.body, isNot(contains('expectedRecordVersion')));
    expect(
      command.body['idempotencyKey'],
      isNot(
        ItemCommand.generate(item.id, 'high', 'Details').body['idempotencyKey'],
      ),
    );
  });
}
