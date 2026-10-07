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
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

/// The wardrobe piece most likely shown as [piece] on a photo: same
/// category, sharing a colour family, and ideally a word of its name.
/// Accessories differ too much within their category, so they also need a
/// shared word that is not a colour ("ring", "glasses"). Null when nothing in
/// the wardrobe fits.
WardrobeItem? likelyMatch(
  LookFoundPiece piece,
  Iterable<WardrobeItem> wardrobe,
) {
  final families = piece.colors.expand(colorFamilies).toSet()..remove('other');
  List<String> words(String name) =>
      name.toLowerCase().split(RegExp(r'[\s\-]+')).toList();
  final pieceWords = words(piece.name).toSet();
  WardrobeItem? best;
  var bestScore = 0;
  for (final item in wardrobe) {
    if (item.state == 'archived' || item.metadata.category != piece.category) {
      continue;
    }
    final itemFamilies = item.metadata.colors.expand(colorFamilies).toSet();
    final colours = families.intersection(itemFamilies).length;
    if (families.isNotEmpty && colours == 0) continue;
    final shared = words(item.metadata.name).where(pieceWords.contains);
    final named = shared.length;
    final shape = shared
        .where((word) => colorFamilies(word).contains('other'))
        .length;
    if (piece.category == 'accessory' && shape == 0) continue;
    final score = 1 + colours * 2 + named;
    if (score > bestScore) {
      best = item;
      bestScore = score;
    }
  }
  return best;
}

/// The wardrobe piece the user said [piece] is on [look], while it is still
/// part of the look.
WardrobeItem? linkedFoundItem(
  LookFoundPiece piece,
  Look look,
  Map<String, WardrobeItem> wardrobe,
) => switch (piece.wardrobeItemId) {
  final id? when look.wardrobeItemIds.contains(id) => wardrobe[id],
  _ => null,
};

/// Everything on a photo look in one list: each piece FORM found on the
/// photo, and pieces the user put on the look by hand. Found pieces are
/// confirmed as a piece already in the Schrank, added as a new one, or
/// skipped, and every answer can be taken back. Tapping a confirmed piece
/// marks it on the photo.
class FoundPieces extends StatefulWidget {
  const FoundPieces({
    required this.look,
    required this.state,
    required this.online,
    required this.selectedId,
    required this.onSelect,
    super.key,
  });

  final Look look;
  final FeedState state;
  final bool online;

  /// The wardrobe piece marked on the photo.
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  State<FoundPieces> createState() => _FoundPiecesState();
}

class _FoundPiecesState extends State<FoundPieces> {
  final _busy = <String>{};

  /// Matches the user said "no" to. The piece is then offered as new.
  final _rejected = <String>{};

  Future<void> _run(String pieceId, Future<void> Function() action) async {
    setState(() => _busy.add(pieceId));
    unawaited(HapticFeedback.lightImpact());
    await runFeedAction(context, action);
    if (mounted) setState(() => _busy.remove(pieceId));
  }

  void _unlink(LookFoundPiece piece, WardrobeItem item) {
    final feed = context.read<FeedCubit>();
    final look = widget.look;
    if (widget.selectedId == item.id) widget.onSelect(null);
    unawaited(
      _run(piece.id, () async {
        await feed.unlinkFound(look, piece);
        if (!mounted) return;
        showFormToast(
          context,
          context.tr(
            LocaleKeys.foundUnlinked,
            namedArgs: {'name': item.metadata.name},
          ),
          action: context.tr(LocaleKeys.proposalsUndo),
          onAction: () => unawaited(
            runFeedAction(context, () => feed.linkFound(look, piece, item.id)),
          ),
        );
      }),
    );
  }

  Future<void> _removeFromWardrobe(
    LookFoundPiece piece,
    WardrobeItem item,
  ) async {
    final confirmed = await confirmFormAction(
      context: context,
      title: context.tr(LocaleKeys.foundRemoveTitle),
      message: context.tr(
        LocaleKeys.foundRemoveBody,
        namedArgs: {'name': item.metadata.name},
      ),
      confirmLabel: context.tr(LocaleKeys.foundRemove),
    );
    if (!confirmed || !mounted) return;
    if (widget.selectedId == item.id) widget.onSelect(null);
    final feed = context.read<FeedCubit>();
    await _run(piece.id, () => feed.removeFoundPiece(widget.look, piece));
  }

  /// The actions on a confirmed piece, in a small sheet.
  Future<void> _openMenu(LookFoundPiece piece, WardrobeItem item) =>
      showFormSheet<void>(
        context: context,
        builder: (sheetContext) {
          void then(VoidCallback action) {
            Navigator.pop(sheetContext);
            action();
          }

          return FormSheet(
            title: item.metadata.name,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                _MenuAction(
                  icon: Icons.checkroom_outlined,
                  label: context.tr(LocaleKeys.lookOpenPiece),
                  onTap: () => then(
                    () => unawaited(context.push('/wardrobe/items/${item.id}')),
                  ),
                ),
                _MenuAction(
                  icon: Icons.link_off,
                  label: context.tr(
                    LocaleKeys.foundUnlink,
                    namedArgs: {'name': item.metadata.name},
                  ),
                  enabled: widget.online,
                  onTap: () => then(() => _unlink(piece, item)),
                ),
                if (piece.added)
                  _MenuAction(
                    icon: Icons.delete_outline,
                    label: context.tr(LocaleKeys.foundRemove),
                    danger: true,
                    enabled: widget.online,
                    onTap: () =>
                        then(() => unawaited(_removeFromWardrobe(piece, item))),
                  ),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final found = look.found;
    final feed = context.read<FeedCubit>();
    final wardrobe = widget.state.itemsById;
    final credits = context.watch<CreditsCubit>().state;
    final reference = look.isReference;
    final linkedIds = {
      for (final piece in found ?? const <LookFoundPiece>[])
        ?linkedFoundItem(piece, look, wardrobe)?.id,
    };
    // On the look, but not tied to anything found on the photo.
    final extra = [
      for (final id in look.wardrobeItemIds)
        if (!linkedIds.contains(id)) ?wardrobe[id],
    ];
    final cost = credits?.metered == false
        ? null
        : context.tr(
            LocaleKeys.lookCostBadge,
            namedArgs: {'cost': '$shelfImageCreditCost'},
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            context.tr(
              reference
                  ? LocaleKeys.foundTitleReference
                  : LocaleKeys.foundTitle,
            ),
            style: FormTokens.heading.copyWith(fontSize: 19),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            context.tr(
              found == null
                  ? LocaleKeys.foundSearching
                  : reference
                  ? LocaleKeys.foundBodyReference
                  : LocaleKeys.foundBody,
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
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                if (found.isEmpty && extra.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      context.tr(LocaleKeys.foundNone),
                      style: FormTokens.body.copyWith(color: FormTokens.muted),
                    ),
                  ),
                for (final (index, piece) in found.indexed)
                  _FoundRow(
                    key: ValueKey(piece.id),
                    index: index,
                    piece: piece,
                    online: widget.online,
                    busy: _busy.contains(piece.id),
                    reference: reference,
                    dismissed: widget.state.dismissedFound.contains(piece.id),
                    linked: linkedFoundItem(piece, look, wardrobe),
                    selected:
                        widget.selectedId != null &&
                        widget.selectedId ==
                            linkedFoundItem(piece, look, wardrobe)?.id,
                    // Someone else's photo shows their pieces, not yours.
                    match: reference || _rejected.contains(piece.id)
                        ? null
                        : likelyMatch(
                            piece,
                            wardrobe.values.where(
                              (item) =>
                                  item.state == 'owning' &&
                                  !look.wardrobeItemIds.contains(item.id),
                            ),
                          ),
                    cost: cost,
                    onLink: (item) => _run(
                      piece.id,
                      () => feed.linkFound(look, piece, item.id),
                    ),
                    onReject: () {
                      unawaited(HapticFeedback.selectionClick());
                      setState(() => _rejected.add(piece.id));
                    },
                    onSkip: () {
                      unawaited(HapticFeedback.selectionClick());
                      feed.dismissFound(piece.id);
                    },
                    onRestore: () {
                      unawaited(HapticFeedback.selectionClick());
                      setState(() => _rejected.remove(piece.id));
                      feed.restoreFound(piece.id);
                    },
                    onAdd: () => _run(
                      piece.id,
                      () => feed.addFoundPiece(
                        look,
                        piece,
                        quality: context.read<QualityCubit>().state.wardrobe,
                        wanting: reference,
                      ),
                    ),
                    onSelect: (item) {
                      unawaited(HapticFeedback.selectionClick());
                      widget.onSelect(
                        widget.selectedId == item.id ? null : item.id,
                      );
                    },
                    onMenu: (item) => unawaited(_openMenu(piece, item)),
                  ),
                if (extra.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Text(
                      context.tr(LocaleKeys.foundExtraTitle),
                      style: FormTokens.small.copyWith(
                        color: FormTokens.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final item in extra)
                    _ExtraRow(
                      key: ValueKey('extra-${item.id}'),
                      item: item,
                      busy: _busy.contains(item.id),
                      selected: widget.selectedId == item.id,
                      online: widget.online,
                      onTap: () {
                        unawaited(HapticFeedback.selectionClick());
                        widget.onSelect(
                          widget.selectedId == item.id ? null : item.id,
                        );
                      },
                      onRemove: () => _run(
                        item.id,
                        () => feed.setLookItems(look.id, [
                          for (final id in look.wardrobeItemIds)
                            if (id != item.id) id,
                        ]),
                      ),
                    ),
                ],
              ],
            ),
          },
        ),
      ],
    );
  }
}

/// One found piece. Confirmed, it shows the wardrobe piece it stands for,
/// marks it on the photo when tapped and keeps its other actions behind
/// "more". With a likely match, it asks "Is this your …?". Otherwise it
/// offers the piece as new: into the Schrank from an own photo, onto the
/// wish list from someone else's. A skipped piece comes back with a tap.
class _FoundRow extends StatelessWidget {
  const _FoundRow({
    required this.index,
    required this.piece,
    required this.online,
    required this.busy,
    required this.reference,
    required this.dismissed,
    required this.linked,
    required this.selected,
    required this.match,
    required this.cost,
    required this.onLink,
    required this.onReject,
    required this.onSkip,
    required this.onRestore,
    required this.onAdd,
    required this.onSelect,
    required this.onMenu,
    super.key,
  });

  final int index;
  final LookFoundPiece piece;
  final bool online;
  final bool busy;
  final bool reference;
  final bool dismissed;
  final WardrobeItem? linked;
  final bool selected;
  final WardrobeItem? match;
  final String? cost;
  final ValueChanged<WardrobeItem> onLink;
  final VoidCallback onReject;
  final VoidCallback onSkip;
  final VoidCallback onRestore;
  final VoidCallback onAdd;
  final ValueChanged<WardrobeItem> onSelect;
  final ValueChanged<WardrobeItem> onMenu;

  @override
  Widget build(BuildContext context) {
    final linked = this.linked;
    final match = this.match;
    final family = piece.colors
        .expand(colorFamilies)
        .where((f) => f != 'other')
        .firstOrNull;
    final open = linked == null && !dismissed;
    final generating =
        linked != null &&
        const ['queued', 'generating'].contains(linked.status);
    final addLabel = context.tr(
      reference ? LocaleKeys.foundAddWanting : LocaleKeys.foundAddOwning,
    );
    const spinner = Padding(
      padding: EdgeInsets.all(12),
      child: SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
    Widget actions() {
      if (match != null) {
        return Row(
          spacing: 8,
          children: [
            Expanded(
              child: FilledButton(
                onPressed: online && !busy ? () => onLink(match) : null,
                child: Text(context.tr(LocaleKeys.foundYes)),
              ),
            ),
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onReject,
                child: Text(context.tr(LocaleKeys.foundNo)),
              ),
            ),
          ],
        );
      }
      return Row(
        spacing: 8,
        children: [
          Expanded(
            child: FilledButton.tonal(
              onPressed: online && !busy ? onAdd : null,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(cost == null ? addLabel : '$addLabel · $cost'),
              ),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onSkip,
            style: TextButton.styleFrom(foregroundColor: FormTokens.muted),
            child: Text(context.tr(LocaleKeys.foundSkip)),
          ),
        ],
      );
    }

    final title = linked != null
        ? linked.metadata.name
        : match != null
        ? context.tr(
            LocaleKeys.foundIsThisYours,
            namedArgs: {'name': match.metadata.name},
          )
        : piece.name;
    final subtitle = linked != null
        ? context.tr(
            generating
                ? LocaleKeys.foundGenerating
                : linked.state == 'wanting'
                ? LocaleKeys.foundInWanting
                : LocaleKeys.foundInWardrobe,
          )
        : match != null
        ? context.tr(LocaleKeys.foundSeenAs, namedArgs: {'name': piece.name})
        : dismissed
        ? context.tr(LocaleKeys.foundSkipped)
        : context.tr(
            reference ? LocaleKeys.foundNewReference : LocaleKeys.foundNewOwn,
          );

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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(FormTokens.cardRadius),
          onTap: linked != null
              ? () => onSelect(linked)
              : dismissed
              ? onRestore
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: FormTokens.easeOut,
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              color: linked != null
                  ? FormTokens.selectedTint
                  : dismissed
                  ? Colors.transparent
                  : FormTokens.surface,
              borderRadius: BorderRadius.circular(FormTokens.cardRadius),
              border: Border.all(
                color: selected
                    ? FormTokens.green
                    : dismissed
                    ? FormTokens.line
                    : Colors.transparent,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Opacity(
                      opacity: dismissed ? 0.5 : 1,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: CurvedAnimation(
                                parent: animation,
                                curve: FormTokens.pop,
                              ),
                              child: child,
                            ),
                        child: switch (linked ?? match) {
                          final item? => _Thumb(
                            key: ValueKey('${item.id}$generating'),
                            item: item,
                            generating: generating,
                          ),
                          null => SizedBox(
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
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FormTokens.body.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: dismissed ? FormTokens.muted : null,
                            ),
                          ),
                          Text(
                            subtitle,
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
                    if (busy && !open)
                      spinner
                    else if (linked != null)
                      IconButton(
                        tooltip: context.tr(LocaleKeys.lookActions),
                        onPressed: () => onMenu(linked),
                        icon: const Icon(
                          Icons.more_horiz,
                          color: FormTokens.green,
                        ),
                      )
                    else if (dismissed)
                      TextButton(
                        onPressed: onRestore,
                        style: TextButton.styleFrom(
                          foregroundColor: FormTokens.green,
                        ),
                        child: Text(context.tr(LocaleKeys.foundRestore)),
                      ),
                  ],
                ),
                if (open) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: busy ? const Center(child: spinner) : actions(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A piece on the look that nothing on the photo stands for, e.g. added in
/// the composer. It can be marked or taken off the look.
class _ExtraRow extends StatelessWidget {
  const _ExtraRow({
    required this.item,
    required this.busy,
    required this.selected,
    required this.online,
    required this.onTap,
    required this.onRemove,
    super.key,
  });

  final WardrobeItem item;
  final bool busy;
  final bool selected;
  final bool online;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(FormTokens.cardRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: FormTokens.surface,
          borderRadius: BorderRadius.circular(FormTokens.cardRadius),
          border: Border.all(
            color: selected ? FormTokens.green : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            _Thumb(item: item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.metadata.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FormTokens.body.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    context.tr(LocaleKeys.foundExtraBody),
                    style: FormTokens.small,
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
            else
              IconButton(
                tooltip: context.tr(LocaleKeys.foundRemoveFromLook),
                onPressed: online ? onRemove : null,
                icon: const Icon(Icons.close, color: FormTokens.muted),
              ),
          ],
        ),
      ),
    ),
  );
}

/// One action in a confirmed piece's sheet.
class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = danger ? FormTokens.danger : FormTokens.ink;
    return Material(
      color: FormTokens.surface,
      borderRadius: BorderRadius.circular(FormTokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              spacing: 12,
              children: [
                Icon(icon, size: 21, color: color),
                Expanded(
                  child: Text(
                    label,
                    style: FormTokens.body.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A wardrobe piece's cut-out. While its catalog image is still being made,
/// a soft sheen stands in for it.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, this.generating = false, super.key});

  final WardrobeItem item;
  final bool generating;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(4),
      color: FormTokens.tileTint(item.id, item.metadata.colors),
      child: generating
          ? const DevelopingSheen(active: true)
          : CachedMedia(
              identity: item.previewIdentity,
              previewPath: item.previewPath,
              online: true,
            ),
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
