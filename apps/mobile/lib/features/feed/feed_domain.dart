import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
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
