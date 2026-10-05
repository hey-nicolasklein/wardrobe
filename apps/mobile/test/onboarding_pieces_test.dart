import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/onboarding/onboarding_pieces.dart';

void main() {
  test('a surprise look has one piece per category and a full base', () {
    for (var seed = 0; seed < 20; seed++) {
      final look = surpriseOnboardingLook(seed);
      final categories = look.map((piece) => piece.category).toList();
      expect(categories.toSet().length, categories.length);
      expect(categories, containsAll(['top', 'pants', 'shoes']));
      expect(look.every((piece) => piece.state == 'owning'), isTrue);
    }
  });

  test('a look around a piece always includes it', () {
    for (final id in ['leather-jacket', 'white-tee', 'shorts', 'ring']) {
      final piece = onboardingPiece(id);
      for (var seed = 0; seed < 10; seed++) {
        final look = surpriseOnboardingLook(seed, around: piece);
        expect(look, contains(piece));
        expect(look.where((entry) => entry.category == piece.category), [
          piece,
        ]);
      }
    }
  });

  test('possible looks grow much faster than pieces', () {
    expect(estimatedLooks(0), 0);
    expect(estimatedLooks(10), greaterThan(10));
    expect(estimatedLooks(40), greaterThan(estimatedLooks(20) * 4));
  });
}
