import 'package:flutter_test/flutter_test.dart';
import 'package:form_mobile/features/onboarding/onboarding_pieces.dart';

void main() {
  test('adding a piece replaces the one of the same category', () {
    final look = toggleOnboardingPiece(const [], onboardingPiece('jersey'));
    final swapped = toggleOnboardingPiece(look, onboardingPiece('white-tee'));
    expect(swapped.map((piece) => piece.id), ['white-tee']);
    final withPants = toggleOnboardingPiece(
      swapped,
      onboardingPiece('shorts'),
    );
    expect(withPants.map((piece) => piece.id), ['white-tee', 'shorts']);
    final removed = toggleOnboardingPiece(
      withPants,
      onboardingPiece('white-tee'),
    );
    expect(removed.map((piece) => piece.id), ['shorts']);
  });

  test('a surprise look has one piece per category and a full base', () {
    for (var seed = 0; seed < 20; seed++) {
      final look = surpriseOnboardingLook(seed);
      final categories = look.map((piece) => piece.category).toList();
      expect(categories.toSet().length, categories.length);
      expect(categories, containsAll(['top', 'pants', 'shoes']));
      expect(look.every((piece) => piece.state == 'owning'), isTrue);
    }
  });

  test('possible looks grow much faster than pieces', () {
    expect(estimatedLooks(0), 0);
    expect(estimatedLooks(10), greaterThan(10));
    expect(estimatedLooks(40), greaterThan(estimatedLooks(20) * 4));
  });
}
