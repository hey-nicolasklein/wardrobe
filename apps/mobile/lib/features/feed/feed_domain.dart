import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';

enum LookFeedView { worn, flat }

class LookGarment {
  const LookGarment({required this.id, this.item});
  final String id;
  final WardrobeItem? item;

  bool get available => item != null;
}

String lookCaption(Look look) => [
  look.concept?.activity,
  look.concept?.scene,
].whereType<String>().join(', ');

/// Whole calendar days between [createdAt] and [now], never negative.
int lookAgeDays(DateTime createdAt, {DateTime? now}) {
  final reference = (now ?? DateTime.now()).toLocal();
  final created = createdAt.toLocal();
  final days = DateTime.utc(
    reference.year,
    reference.month,
    reference.day,
  ).difference(DateTime.utc(created.year, created.month, created.day)).inDays;
  return days < 0 ? 0 : days;
}

/// Qualities a look can be upgraded to, lowest first. Empty at `high`.
List<String> higherQualities(String quality) =>
    qualities.skip(qualities.indexOf(quality) + 1).toList();

List<LookGarment> lookGarments(
  Look look,
  Map<String, WardrobeItem> itemsById, {
  List<String>? pendingItemIds,
}) {
  final ids = look.wardrobeItemIds.isNotEmpty || look.isReady
      ? look.wardrobeItemIds
      : pendingItemIds ?? const [];
  return [
    for (final id in ids) LookGarment(id: id, item: itemsById[id]),
  ];
}

List<Look> readyLooksForItem(String itemId, Iterable<Look> looks) => [
  for (final look in looks)
    if (look.isReady &&
        look.assetId != null &&
        look.wardrobeItemIds.contains(itemId))
      look,
];

List<WardrobeItem> eligibleComposerItems(List<CachedItem> records) => [
  for (final record in records)
    if (record.item.state != 'archived' &&
        record.item.currentShelfImageVersionId != null)
      record.item,
];

/// A stack on the Looks screen: a set of looks gathered by one mission.
sealed class LookStack {
  const LookStack();
}

class AllLooksStack extends LookStack {
  const AllLooksStack();
}

/// Looks made for [occasion]; null is the surprise occasion. Try-ons have
/// their own stack.
class OccasionStack extends LookStack {
  const OccasionStack(this.occasion);
  final String? occasion;
}

class TryOnStack extends LookStack {
  const TryOnStack();
}

class SavedStack extends LookStack {
  const SavedStack();
}

/// Looks that include the wardrobe piece [itemId].
class PieceStack extends LookStack {
  const PieceStack(this.itemId);
  final String itemId;
}

/// Looks with at least one piece in the colour family [family], see
/// [colorFamilies].
class ColorStack extends LookStack {
  const ColorStack(this.family);
  final String family;
}

/// Looks the user filed into the Sammlung [collectionId].
class CollectionStack extends LookStack {
  const CollectionStack(this.collectionId);
  final String collectionId;
}

/// [collections] maps each Sammlung's id to its look ids.
bool inLookStack(
  LookStack stack,
  Look look, {
  required Map<String, WardrobeItem> itemsById,
  required bool saved,
  Map<String, List<String>> collections = const {},
}) => switch (stack) {
  AllLooksStack() => true,
  OccasionStack(:final occasion) =>
    !look.isTryOn && look.settings?.occasion == occasion,
  TryOnStack() => look.isTryOn,
  SavedStack() => saved,
  CollectionStack(:final collectionId) =>
    collections[collectionId]?.contains(look.id) ?? false,
  PieceStack(:final itemId) => look.wardrobeItemIds.contains(itemId),
  ColorStack(:final family) => look.wardrobeItemIds.any(
    (id) =>
        itemsById[id]?.metadata.colors.any(
          (color) => colorFamilies(color).contains(family),
        ) ??
        false,
  ),
};

/// Every wardrobe piece that appears in [looks], with the looks it appears
/// in, most combined first. Ties go to the piece worn most recently. [looks]
/// is newest first, so each list is too.
List<(WardrobeItem, List<CachedLook>)> pieceStacks(
  List<CachedLook> looks,
  Map<String, WardrobeItem> itemsById,
) {
  final byItem = <String, List<CachedLook>>{};
  for (final record in looks) {
    for (final id in record.look.wardrobeItemIds.toSet()) {
      if (itemsById[id] case final item? when item.state != 'archived') {
        (byItem[id] ??= []).add(record);
      }
    }
  }
  return _byCount([
    for (final MapEntry(:key, :value) in byItem.entries)
      (itemsById[key]!, value),
  ]);
}

/// The colour families present in [looks]' pieces, with their looks, most
/// frequent first. Unrecognised colours ("other") are left out.
List<(String, List<CachedLook>)> colorStacks(
  List<CachedLook> looks,
  Map<String, WardrobeItem> itemsById,
) {
  final byFamily = <String, List<CachedLook>>{};
  for (final record in looks) {
    final families = {
      for (final id in record.look.wardrobeItemIds)
        for (final color in itemsById[id]?.metadata.colors ?? const <String>[])
          ...colorFamilies(color),
    }..remove('other');
    for (final family in families) {
      (byFamily[family] ??= []).add(record);
    }
  }
  return _byCount([
    for (final MapEntry(:key, :value) in byFamily.entries) (key, value),
  ]);
}

/// Sorts by look count, largest first, keeping the given order among ties.
List<(T, List<CachedLook>)> _byCount<T>(List<(T, List<CachedLook>)> stacks) {
  final order = {for (final (index, stack) in stacks.indexed) stack: index};
  return stacks..sort((a, b) {
    final byCount = b.$2.length.compareTo(a.$2.length);
    return byCount != 0 ? byCount : order[a]!.compareTo(order[b]!);
  });
}
