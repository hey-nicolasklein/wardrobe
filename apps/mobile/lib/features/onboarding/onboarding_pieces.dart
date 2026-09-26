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

/// Adds [piece] to [look], replacing the piece of the same category, or
/// removes it when it is already part of the look.
List<OnboardingPiece> toggleOnboardingPiece(
  List<OnboardingPiece> look,
  OnboardingPiece piece,
) {
  if (look.any((entry) => entry.id == piece.id)) {
    return [
      for (final entry in look)
        if (entry.id != piece.id) entry,
    ];
  }
  return [
    for (final entry in look)
      if (entry.category != piece.category) entry,
    piece,
  ];
}

/// A random complete outfit from the owned demo pieces: always a top, pants
/// and shoes, sometimes a jacket and an accessory.
List<OnboardingPiece> surpriseOnboardingLook(int seed) {
  final random = Random(seed);
  OnboardingPiece pick(String category) {
    final options = onboardingPieces
        .where((piece) => piece.category == category && piece.state == 'owning')
        .toList();
    return options[random.nextInt(options.length)];
  }

  return [
    pick('top'),
    if (random.nextBool()) pick('jacket'),
    pick('pants'),
    pick('shoes'),
    if (random.nextInt(3) == 0) pick('accessory'),
  ];
}

/// A playful estimate of distinct outfits in a wardrobe of [pieces]: every
/// top, pants and shoes combination, with or without each jacket.
int estimatedLooks(int pieces) {
  int share(double part) => (pieces * part).floor();
  return share(0.35) * share(0.25) * share(0.2) * (share(0.2) + 1);
}
