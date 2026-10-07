import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/look_card.dart';
import 'package:form_mobile/features/feed/look_stacks.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/features/settings/quality_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/credits_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:go_router/go_router.dart';

/// The wardrobe piece most likely shown as [piece] on a photo: same
/// category, sharing a colour family, and ideally a word of its name. Null
/// when nothing in the wardrobe fits.
WardrobeItem? likelyMatch(
  LookFoundPiece piece,
  Iterable<WardrobeItem> wardrobe,
) {
  final families = piece.colors.expand(colorFamilies).toSet()..remove('other');
  final words = piece.name.toLowerCase().split(RegExp(r'\s+')).toSet();
  WardrobeItem? best;
  var bestScore = 0;
  for (final item in wardrobe) {
    if (item.state == 'archived' || item.metadata.category != piece.category) {
      continue;
    }
    final itemFamilies = item.metadata.colors.expand(colorFamilies).toSet();
    final colours = families.intersection(itemFamilies).length;
    if (families.isNotEmpty && colours == 0) continue;
    final named = item.metadata.name
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where(words.contains)
        .length;
    final score = 1 + colours * 2 + named;
    if (score > bestScore) {
      best = item;
      bestScore = score;
    }
  }
  return best;
}

/// The pieces FORM found on a photo look. Each one is matched to a piece
/// already in the Schrank with one tap, or added as a new piece. Nothing
/// joins the wardrobe by itself.
class FoundPieces extends StatefulWidget {
  const FoundPieces({
    required this.look,
    required this.state,
    required this.online,
    super.key,
  });

  final Look look;
  final FeedState state;
  final bool online;

  @override
  State<FoundPieces> createState() => _FoundPiecesState();
}

class _FoundPiecesState extends State<FoundPieces> {
  final _busy = <String>{};

  Future<void> _run(String pieceId, Future<void> Function() action) async {
    setState(() => _busy.add(pieceId));
    unawaited(HapticFeedback.lightImpact());
    await runFeedAction(context, action);
    if (mounted) setState(() => _busy.remove(pieceId));
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final found = look.found;
    final feed = context.read<FeedCubit>();
    final wardrobe = widget.state.itemsById;
    final credits = context.watch<CreditsCubit>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            context.tr(LocaleKeys.foundTitle),
            style: FormTokens.heading.copyWith(fontSize: 19),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            context.tr(
              found == null ? LocaleKeys.foundSearching : LocaleKeys.foundBody,
            ),
            style: FormTokens.small,
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: const Duration(milliseconds: 360),
          curve: FormTokens.easeOut,
          alignment: Alignment.topCenter,
          child: switch (found) {
            null => const _SearchingRows(),
            [] => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                context.tr(LocaleKeys.foundNone),
                style: FormTokens.body.copyWith(color: FormTokens.muted),
              ),
            ),
            _ => Column(
              spacing: 8,
              children: [
                for (final (index, piece) in found.indexed)
                  _FoundRow(
                    key: ValueKey(piece.id),
                    index: index,
                    piece: piece,
                    online: widget.online,
                    busy: _busy.contains(piece.id),
                    linked: _linkedItem(piece, look, wardrobe),
                    match: likelyMatch(
                      piece,
                      wardrobe.values.where(
                        (item) => !look.wardrobeItemIds.contains(item.id),
                      ),
                    ),
                    cost: credits?.metered == false
                        ? null
                        : context.tr(
                            LocaleKeys.lookCostBadge,
                            namedArgs: {'cost': '$shelfImageCreditCost'},
                          ),
                    onLink: (item) => _run(
                      piece.id,
                      () => feed.setLookItems(look.id, [
                        ...look.wardrobeItemIds,
                        item.id,
                      ]),
                    ),
                    onAdd: () => _run(
                      piece.id,
                      () => feed.addFoundPiece(
                        look,
                        piece,
                        quality: context.read<QualityCubit>().state.wardrobe,
                      ),
                    ),
                  ),
              ],
            ),
          },
        ),
      ],
    );
  }

  /// The wardrobe piece [piece] already stands for in [look]: the one it was
  /// added as, or one linked to the look in the same category.
  static WardrobeItem? _linkedItem(
    LookFoundPiece piece,
    Look look,
    Map<String, WardrobeItem> wardrobe,
  ) {
    if (piece.wardrobeItemId case final id?) {
      if (look.wardrobeItemIds.contains(id)) return wardrobe[id];
    }
    final linked = [
      for (final id in look.wardrobeItemIds)
        if (wardrobe[id] case final item?
            when item.metadata.category == piece.category)
          item,
    ];
    return likelyMatch(piece, linked);
  }
}

/// One found piece: its colour and name, and what it is in the wardrobe.
class _FoundRow extends StatelessWidget {
  const _FoundRow({
    required this.index,
    required this.piece,
    required this.online,
    required this.busy,
    required this.linked,
    required this.match,
    required this.cost,
    required this.onLink,
    required this.onAdd,
    super.key,
  });

  final int index;
  final LookFoundPiece piece;
  final bool online;
  final bool busy;
  final WardrobeItem? linked;
  final WardrobeItem? match;
  final String? cost;
  final ValueChanged<WardrobeItem> onLink;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final linked = this.linked;
    final match = this.match;
    final family = piece.colors
        .expand(colorFamilies)
        .where((f) => f != 'other')
        .firstOrNull;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + 70 * index.clamp(0, 6)),
      curve: FormTokens.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 14),
          child: child,
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: FormTokens.easeOut,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: linked != null ? FormTokens.selectedTint : FormTokens.surface,
          borderRadius: BorderRadius.circular(FormTokens.cardRadius),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: FormTokens.pop,
                ),
                child: child,
              ),
              child: linked != null
                  ? _Thumb(key: ValueKey(linked.id), item: linked)
                  : SizedBox(
                      key: const ValueKey('dot'),
                      width: 44,
                      height: 44,
                      child: Center(
                        child: ColorDot(
                          color: colorFamilySwatches[family],
                          size: 22,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    linked?.metadata.name ?? piece.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FormTokens.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    linked != null
                        ? context.tr(LocaleKeys.foundInWardrobe)
                        : match != null
                        ? context.tr(
                            LocaleKeys.foundMaybe,
                            namedArgs: {'name': match.metadata.name},
                          )
                        : context.tr('categories.${piece.category}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FormTokens.small.copyWith(
                      color: linked != null
                          ? FormTokens.green
                          : FormTokens.noteInk,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (linked != null)
              IconButton(
                tooltip: context.tr(LocaleKeys.lookOpenPiece),
                onPressed: () => context.push('/wardrobe/items/${linked.id}'),
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: FormTokens.green,
                ),
              )
            else ...[
              if (match != null)
                TextButton(
                  onPressed: online ? () => onLink(match) : null,
                  child: Text(context.tr(LocaleKeys.foundLink)),
                ),
              Tooltip(
                message: cost == null
                    ? context.tr(LocaleKeys.foundAdd)
                    : '${context.tr(LocaleKeys.foundAdd)} · $cost',
                child: IconButton.filledTonal(
                  onPressed: online ? onAdd : null,
                  icon: const Icon(Icons.add, size: 20),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, super.key});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: FormTokens.tileTint(item.id, item.metadata.colors),
      borderRadius: BorderRadius.circular(10),
    ),
    child: CachedMedia(
      identity: item.previewIdentity,
      previewPath: item.previewPath,
      online: true,
    ),
  );
}

/// Placeholder rows while the photo is analysed, under a drifting sheen.
class _SearchingRows extends StatelessWidget {
  const _SearchingRows();

  @override
  Widget build(BuildContext context) => Column(
    spacing: 8,
    children: [
      for (var i = 0; i < 3; i++)
        ClipRRect(
          borderRadius: BorderRadius.circular(FormTokens.cardRadius),
          child: SizedBox(
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: FormTokens.surface.withValues(alpha: 1 - i * 0.25),
                ),
                const DevelopingSheen(active: true),
              ],
            ),
          ),
        ),
    ],
  );
}
