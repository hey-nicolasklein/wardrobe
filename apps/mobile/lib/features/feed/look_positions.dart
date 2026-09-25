class LookItemPosition {
  const LookItemPosition({
    required this.x,
    required this.y,
    required this.size,
    required this.originX,
    required this.originY,
    required this.originScale,
    required this.order,
    required this.count,
  });

  final double x;
  final double y;
  final double size;
  final double originX;
  final double originY;
  final double originScale;
  final int order;
  final int count;
}

const _lookBodyRegions = <String, List<double>>{
  'hat': [40, 5, 20, 15],
  'scarf': [39, 22, 22, 22],
  'accessory': [38, 12, 24, 10],
  'top': [32, 24, 36, 32],
  'jacket': [27, 22, 46, 38],
  'dress': [30, 24, 40, 61],
  'bag': [57, 43, 22, 24],
  'pants': [35, 53, 30, 37],
  'skirt': [32, 51, 36, 27],
  'shoes': [33, 87, 34, 10],
};

double _verticalCenter(List<double> region) => region[1] + region[3] / 2;

/// Where each garment sits once revealed and which body region it starts
/// from, mirroring `lookItemPositions` in the PWA's `app.js`.
List<LookItemPosition> lookItemPositions(List<String> categories) {
  final count = categories.length;
  if (count == 0) return [];
  final columns = count <= 2
      ? 1
      : count <= 6
      ? 2
      : 3;
  final rows = (count / columns).ceil();
  const gap = 3.0;
  final rowHeight = (92 - gap * (rows - 1)) / rows;
  final cellWidth = (92 - gap * (columns - 1)) / columns;
  final indices = List<int>.generate(count, (index) => index)
    ..sort((a, b) {
      final regionA =
          _lookBodyRegions[categories[a]] ?? _lookBodyRegions['top']!;
      final regionB =
          _lookBodyRegions[categories[b]] ?? _lookBodyRegions['top']!;
      return _verticalCenter(regionA).compareTo(_verticalCenter(regionB));
    });
  final styles = List<LookItemPosition?>.filled(count, null);
  for (var rank = 0; rank < indices.length; rank++) {
    final index = indices[rank];
    final row = rank ~/ columns;
    final column = rank % columns;
    final inRow = [
      columns,
      count - row * columns,
    ].reduce((a, b) => a < b ? a : b);
    final size = [
      if (inRow == 1) 82.0 else cellWidth,
      rowHeight * 1.25,
    ].reduce((a, b) => a < b ? a : b);
    final x = inRow == 1
        ? count == 2
              ? (row == 0 ? 4 + size / 2 : 96 - size / 2)
              : 50.0
        : 4 + cellWidth / 2 + column * (cellWidth + gap);
    final y = 4 + rowHeight / 2 + row * (rowHeight + gap);
    final region =
        _lookBodyRegions[categories[index]] ?? _lookBodyRegions['top']!;
    final scale = [
      region[2] / size,
      region[3] * 1.25 / size,
      0.9,
    ].reduce((a, b) => a < b ? a : b);
    styles[index] = LookItemPosition(
      x: x,
      y: y,
      size: size,
      originX: region[0] + region[2] / 2,
      originY: region[1] + region[3] / 2,
      originScale: scale,
      order: rank,
      count: count,
    );
  }
  return styles.cast<LookItemPosition>();
}
