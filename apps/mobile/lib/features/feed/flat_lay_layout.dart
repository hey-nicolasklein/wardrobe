import 'package:form_mobile/models/wardrobe.dart';

class FlatLayPlacement {
  const FlatLayPlacement({
    required this.item,
    required this.x,
    required this.y,
    required this.size,
    required this.angle,
  });

  final WardrobeItem item;
  final double x;
  final double y;
  final double size;
  final double angle;
}

const _order = [
  'hat',
  'top',
  'dress',
  'jacket',
  'pants',
  'skirt',
  'scarf',
  'bag',
  'shoes',
];

List<FlatLayPlacement> flatLayLayout(List<WardrobeItem> garments) {
  final sorted = [...garments]
    ..sort((a, b) {
      int rank(WardrobeItem item) {
        final index = _order.indexOf(item.metadata.category);
        return index < 0 ? _order.length : index;
      }

      final byCategory = rank(a).compareTo(rank(b));
      if (byCategory != 0) return byCategory;
      return a.id.compareTo(b.id);
    });
  if (sorted.isEmpty) return [];
  if (sorted.length == 1) {
    return [
      FlatLayPlacement(item: sorted.single, x: 50, y: 61, size: 80, angle: -3),
    ];
  }
  final kinds = sorted.map((item) => item.metadata.category).toList();
  final uniqueKinds = kinds.toSet();
  if (sorted.length > 6 ||
      uniqueKinds.length != kinds.length ||
      (kinds.contains('top') &&
          kinds.contains('dress') &&
          kinds.contains('jacket')) ||
      (kinds.contains('pants') && kinds.contains('skirt')) ||
      !kinds.any(
        (kind) => ['top', 'jacket', 'dress', 'pants', 'skirt'].contains(kind),
      )) {
    final columns = sorted.length > 6 ? 3 : 2;
    final rows = (sorted.length / columns).ceil();
    final cellWidth = 90 / columns;
    final cellHeight = 113 / rows;
    return [
      for (var index = 0; index < sorted.length; index++)
        () {
          final row = index ~/ columns;
          final inRow = columns < sorted.length - row * columns
              ? columns
              : sorted.length - row * columns;
          return FlatLayPlacement(
            item: sorted[index],
            x: 50 + (index % columns - (inRow - 1) / 2) * cellWidth,
            y: 6 + (row + 0.5) * cellHeight,
            size:
                [cellWidth, cellHeight].reduce((a, b) => a < b ? a : b) * 0.92,
            angle: index.isOdd ? 4 : -4,
          );
        }(),
    ];
  }
  final dress = kinds.contains('dress');
  final outer = kinds.contains('jacket');
  final sidePieces = kinds.any(
    (kind) => ['jacket', 'bag', 'scarf', 'hat'].contains(kind),
  );
  final templates = dress
      ? <String, List<double>>{
          'dress': [35, 58, 65, -3],
          'jacket': [77, 33, 39, 6],
          'top': [76, 29, 37, -4],
          'pants': [76, 66, 36, 3],
          'skirt': [75, 65, 35, 4],
          'bag': [77, 77, 29, 7],
          'shoes': [63, 108, 32, -6],
          'hat': [32, 16, 23, -8],
          'scarf': [78, 52, 25, 8],
        }
      : <String, List<double>>{
          'top': [
            if (outer) 30 else sidePieces ? 39 : 50,
            30,
            if (outer) 49 else 57,
            -4,
          ],
          'jacket': [
            if (kinds.contains('top')) 75 else 36,
            34,
            if (kinds.contains('top')) 43 else 58,
            5,
          ],
          'pants': [if (sidePieces) 35 else 45, 81, 53, 2],
          'skirt': [if (sidePieces) 35 else 45, 79, 51, -3],
          'bag': [78, 77, 30, 7],
          'shoes': [72, 109, 31, -6],
          'hat': [78, 15, 24, -8],
          'scarf': [78, 53, 26, 8],
          'dress': [35, 60, 65, -3],
        };
  return [
    for (var index = 0; index < sorted.length; index++)
      () {
        final category = sorted[index].metadata.category;
        final template = templates[category] ?? [76, 54 + index * 6.0, 26, 4];
        return FlatLayPlacement(
          item: sorted[index],
          x: template[0],
          y: template[1],
          size: template[2],
          angle: template[3],
        );
      }(),
  ];
}
