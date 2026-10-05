import 'dart:math';

import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/models/wardrobe.dart';

/// A real wardrobe piece bundled with the app, so onboarding can show a
/// living wardrobe before the person has added anything.
/// Images live in `assets/onboarding/<id>.webp`.
class OnboardingPiece {
  const OnboardingPiece(this.id, this.category, {this.state = 'owning'});

  final String id;
  final String category;
  final String state;

  String get asset => 'assets/onboarding/$id.webp';

  /// A stand-in record for widgets that expect a wardrobe item, such as the
  /// flat lay layout.
  WardrobeItem get item => WardrobeItem(
    id: id,
    sourcePhotoId: 'onboarding',
    state: state,
    status: 'ready',
    metadata: ItemMetadata(
      name: id,
      category: category,
      colors: const ['other'],
      notes: null,
    ),
    currentShelfImageVersionId: 'onboarding',
    recordVersion: 0,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  LookGarment get garment => LookGarment(id: id, item: item);
}

const onboardingPieces = [
  OnboardingPiece('leather-jacket', 'jacket'),
  OnboardingPiece('jersey', 'top'),
  OnboardingPiece('balloon-pants', 'pants'),
  OnboardingPiece('maroon-sneaker', 'shoes'),
  OnboardingPiece('sunglasses', 'accessory'),
  OnboardingPiece('teddy-coat', 'jacket'),
  OnboardingPiece('turtleneck', 'top'),
  OnboardingPiece('brown-trousers', 'pants'),
  OnboardingPiece('high-top', 'shoes'),
  OnboardingPiece('puffer', 'jacket'),
  OnboardingPiece('striped-shirt', 'top'),
  OnboardingPiece('shorts', 'pants'),
  OnboardingPiece('white-sneaker', 'shoes'),
  OnboardingPiece('ring', 'accessory'),
  OnboardingPiece('croc-jacket', 'jacket'),
  OnboardingPiece('black-shirt', 'top'),
  OnboardingPiece('black-pants', 'pants'),
  OnboardingPiece('runner', 'shoes'),
  OnboardingPiece('leopard-jacket', 'jacket'),
  OnboardingPiece('white-tee', 'top'),
  OnboardingPiece('glasses', 'accessory'),
  OnboardingPiece('olive-jacket', 'jacket', state: 'wanting'),
  OnboardingPiece('black-sneaker', 'shoes', state: 'wanting'),
];

OnboardingPiece onboardingPiece(String id) =>
    onboardingPieces.firstWhere((piece) => piece.id == id);

/// A random complete outfit from the owned demo pieces: always a top, pants
/// and shoes, sometimes a jacket and an accessory. [around] is always part of
/// it, in place of the random pick for its category.
List<OnboardingPiece> surpriseOnboardingLook(
  int seed, {
  OnboardingPiece? around,
}) {
  final random = Random(seed);
  OnboardingPiece pick(String category) {
    if (around?.category == category) return around!;
    final options = onboardingPieces
        .where((piece) => piece.category == category && piece.state == 'owning')
        .toList();
    return options[random.nextInt(options.length)];
  }

  return [
    pick('top'),
    if (around?.category == 'jacket' || random.nextBool()) pick('jacket'),
    pick('pants'),
    pick('shoes'),
    if (around?.category == 'accessory' || random.nextInt(3) == 0)
      pick('accessory'),
  ];
}

/// A rough estimate of looks that actually work in a wardrobe of [pieces].
/// Not every combination goes together, so it grows with the square of the
/// pieces rather than with every possible combination.
int estimatedLooks(int pieces) => pieces * pieces ~/ 6;
