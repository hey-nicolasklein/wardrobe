import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/feed/look_positions.dart';

void main() {
  test('lookItemPositions ranks pieces from head to feet', () {
    final positions = lookItemPositions(['shoes', 'top', 'hat']);
    expect(positions, hasLength(3));
    expect(positions.map((p) => p.order).toList(), [2, 1, 0]);
    expect(positions.every((p) => p.count == 3), isTrue);
    expect(positions[1].originX, closeTo(50, 0.01));
  });

  test('accessories start near the face, unknown categories at the top', () {
    final positions = lookItemPositions(['accessory', 'unknown']);
    expect(positions[0].originY, closeTo(17, 0.01));
    expect(positions[1].originY, closeTo(40, 0.01));
  });
}
