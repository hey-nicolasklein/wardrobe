import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/settings/character/collage_geometry.dart';

void main() {
  test('one to four photos tile the exact PWA canvas without gaps', () {
    expect(collageLayout(1), [(left: 0, top: 0, width: 864, height: 1536)]);
    expect(collageLayout(2), [
      (left: 0, top: 0, width: 864, height: 768),
      (left: 0, top: 768, width: 864, height: 768),
    ]);
    expect(collageLayout(3), [
      (left: 0, top: 0, width: 864, height: 768),
      (left: 0, top: 768, width: 432, height: 768),
      (left: 432, top: 768, width: 432, height: 768),
    ]);
    expect(collageLayout(4), [
      (left: 0, top: 0, width: 432, height: 768),
      (left: 432, top: 0, width: 432, height: 768),
      (left: 0, top: 768, width: 432, height: 768),
      (left: 432, top: 768, width: 432, height: 768),
    ]);
    for (final count in [0, 5]) {
      expect(() => collageLayout(count), throwsFormatException);
    }
  });

  test('crop bounds cover every tile at all zooms and pan extremes', () {
    for (final size in [(2400, 1600), (1600, 2400), (300, 200)]) {
      for (var count = 1; count <= 4; count++) {
        for (final tile in collageLayout(count)) {
          for (final zoom in [1.0, 3.0, 6.0]) {
            for (final edge in [0.0, 0.5, 1.0]) {
              final crop = PhotoCrop(zoom: zoom, x: edge, y: edge);
              final b = crop.bounds(size.$1, size.$2, tile);
              expect(b.x, greaterThanOrEqualTo(0));
              expect(b.y, greaterThanOrEqualTo(0));
              expect(b.x + b.width, lessThanOrEqualTo(size.$1 + 0.0001));
              expect(b.y + b.height, lessThanOrEqualTo(size.$2 + 0.0001));
              expect(
                b.width / b.height,
                closeTo(tile.width / tile.height, 0.00001),
              );
            }
          }
        }
      }
    }
  });

  test('pan clamps at edges and zoom clamps to the PWA slider', () {
    final tile = collageLayout(1).single;
    const crop = PhotoCrop(zoom: 2);
    expect(crop.withZoom(0).zoom, 1);
    expect(crop.withZoom(9).zoom, 6);
    final left = crop.pan(2400, 2400, tile, 100, 100);
    expect((left.x, left.y), (0, 0));
    final right = crop.pan(2400, 2400, tile, -100, -100);
    expect((right.x, right.y), (1, 1));
    expect(const PhotoCrop().pan(864, 1536, tile, 4, 4).x, 0.5);
  });

  test('resolution warning uses cropped source pixels, including zoom', () {
    final tile = collageLayout(1).single;
    expect(const PhotoCrop().lowResolution(864, 1536, tile), false);
    expect(const PhotoCrop(zoom: 1.01).lowResolution(864, 1536, tile), true);
    expect(const PhotoCrop().lowResolution(432, 768, tile), true);
    expect(const PhotoCrop().lowResolution(1600, 2400, tile), false);
  });
}
