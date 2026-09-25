import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/flat_lay_layout.dart';
import 'package:form_mobile/models/wardrobe.dart';

import 'support/wardrobe_fixtures.dart';

WardrobeItem item(String id, String category) => WardrobeItem.fromJson(
  itemJson(id: id)
    ..['metadata'] = {
      ...itemJson()['metadata'] as Map<String, dynamic>,
      'category': category,
      'name': id,
    },
);

void main() {
  test('flat lay sorts by category order then id', () {
    final shoes = item('wardrobe-item-shoes', 'shoes');
    final top = item('wardrobe-item-top', 'top');
    final hat = item('wardrobe-item-hat', 'hat');
    final layout = flatLayLayout([shoes, top, hat]);
    expect(layout.map((p) => p.item.id), [
      hat.id,
      top.id,
      shoes.id,
    ]);
  });

  test('single garment uses centered template', () {
    final layout = flatLayLayout([item('wardrobe-item-0001', 'top')]);
    expect(layout, hasLength(1));
    expect(layout.single.x, 50);
    expect(layout.single.y, 61);
  });

  test('conflicting categories fall back to grid layout', () {
    final top = item('wardrobe-item-a', 'top');
    final dress = item('wardrobe-item-b', 'dress');
    final jacket = item('wardrobe-item-c', 'jacket');
    final layout = flatLayLayout([top, dress, jacket]);
    expect(layout, hasLength(3));
    expect(layout.every((p) => p.size > 0), isTrue);
  });
}
