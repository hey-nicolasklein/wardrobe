import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/collection_sheet.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/found_pieces.dart';
import 'package:form_mobile/features/feed/look_actions.dart';
import 'package:form_mobile/features/feed/look_card.dart';
import 'package:form_mobile/features/feed/look_collections_cubit.dart';
import 'package:form_mobile/features/feed/look_positions.dart';
import 'package:form_mobile/features/feed/look_stacks.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/credits_repository.dart';
import 'package:form_mobile/repository/look_collection_repository.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';

/// Whether [record] is shown as a [FittingRoomCard]. Generated looks that
/// are still developing or failed keep `LookCard`, which animates those
/// states.
bool fittingRoomApplies(CachedLook record) =>
    record.look.isReady &&
    (record.look.assetId != null || !record.look.isGenerated);

/// One way to see a look on its card: its pieces laid out flat, or one of
/// its photos.
class _Layer {
  const _Layer.flat() : record = null;
  const _Layer.photo(CachedLook this.record);

  /// Null for the flat lay.
  final CachedLook? record;

  String get id => record?.look.id ?? 'flat';
}

/// A ready look as a fitting room: a photo of it, or its pieces laid out
/// flat, with a strip of its pieces. Picking a piece marks where it sits.
/// A combination also shows the images made of it, and offers new ones; a
/// photo look lists the pieces found on the photo. Below, everything is
/// derived from the wardrobe: which pieces you own, the look's colours and
/// the Sammlungen it is filed in.
class FittingRoomCard extends StatefulWidget {
  const FittingRoomCard({
    required this.record,
    required this.state,
    required this.garments,
    required this.online,
    required this.onMenu,
    required this.onOpenStack,
    this.onRetry,
    super.key,
  });

  final CachedLook record;
  final FeedState state;
  final List<LookGarment> garments;
  final bool online;

  /// Opens a look's actions: the image on show, or the look itself.
  final ValueChanged<Look> onMenu;
  final ValueChanged<LookStack> onOpenStack;

  /// Retries a failed image of a combination.
  final ValueChanged<Look>? onRetry;

  @override
  State<FittingRoomCard> createState() => _FittingRoomCardState();
}

class _FittingRoomCardState extends State<FittingRoomCard> {
  String? _selectedId;

  /// The layer the user picked. Null follows the newest image.
  String? _layerId;

  /// The layers in pill order: the look's own photo, then images newest
  /// first, then the flat lay, which every look has.
  List<_Layer> _layers() {
    final look = widget.record.look;
    return [
      if (look.assetId != null) _Layer.photo(widget.record),
      if (look.isCombination)
        for (final image in widget.state.imagesOf(look.id)) _Layer.photo(image),
      const _Layer.flat(),
    ];
  }

  /// Set after a tap on the photo that hit no piece. Shows where the pieces
  /// can be tapped until it runs out.
  Timer? _hints;

  @override
  void dispose() {
    _hints?.cancel();
    super.dispose();
  }

  void _showHints() {
    _hints?.cancel();
    _hints = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _hints = null);
    });
  }

  /// The piece whose body region centre is closest to [point], given in
  /// percent of the photo, if the tap landed roughly on it.
  String? _garmentNear(Offset point, List<LookItemPosition> positions) {
    String? nearest;
    var best = 22.0;
    for (var i = 0; i < positions.length; i++) {
      final garment = widget.garments[i];
      if (garment.item == null) continue;
      final distance =
          (point - Offset(positions[i].originX, positions[i].originY)).distance;
      if (distance < best) {
        best = distance;
        nearest = garment.id;
      }
    }
    return nearest;
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.record.look;
    final garments = widget.garments;
    final layers = _layers();
    final layer =
        layers.where((l) => l.id == _layerId).firstOrNull ??
        layers.firstWhere(
          (l) =>
              l.record == null ||
              !l.record!.look.isGenerated ||
              l.record!.look.isReady,
          orElse: () => layers.last,
        );
    final shown = layer.record;
    final items = [
      for (final garment in garments) ?garment.item,
    ];
    final filedIn = collectionsOf(
      context.watch<LookCollectionsCubit>().state,
      look.id,
    );
    final positions = lookItemPositions(
      garments.map((g) => g.item?.metadata.category ?? 'top').toList(),
    );
    final selectedIndex = garments.indexWhere((g) => g.id == _selectedId);
    final selected = selectedIndex < 0 ? null : garments[selectedIndex];
    final meta = [
      ?_occasionLabel(context, look.settings?.occasion),
      lookDateText(context, look.createdAt),
    ].join(' · ');
    final families = {
      for (final item in items)
        for (final color in item.metadata.colors) ...colorFamilies(color),
    }..remove('other');
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: FormTokens.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.97,
                      end: 1,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(layer.id),
                  child: shown == null
                      ? _FlatStage(
                          garments: garments,
                          online: widget.online,
                          selectedId: _selectedId,
                          onGarmentTap: (id) => setState(
                            () => _selectedId = id == _selectedId ? null : id,
                          ),
                        )
                      : !shown.look.isReady
                      ? _ImageInProgress(
                          look: shown.look,
                          garments: garments,
                          online: widget.online,
                          onRetry: widget.onRetry == null
                              ? null
                              : () => widget.onRetry!(shown.look),
                        )
                      : _LookPhoto(
                          record: shown,
                          online: widget.online,
                          onTapAt: (point) {
                            final id = _garmentNear(point, positions);
                            setState(() {
                              _selectedId = id == _selectedId ? null : id;
                              if (id == null) {
                                _showHints();
                              } else {
                                _hints?.cancel();
                                _hints = null;
                              }
                            });
                          },
                          overlay: (size) => Stack(
                            fit: StackFit.expand,
                            children: [
                              _TapAreaHints(
                                visible: _hints != null,
                                points: [
                                  for (var i = 0; i < positions.length; i++)
                                    if (garments[i].item != null)
                                      Offset(
                                        positions[i].originX,
                                        positions[i].originY,
                                      ),
                                ],
                                size: size,
                              ),
                              _PieceMarker(
                                garment: selected,
                                position:
                                    selectedIndex < 0 ||
                                        selectedIndex >= positions.length
                                    ? null
                                    : positions[selectedIndex],
                                size: size,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: () => widget.onMenu(shown?.look ?? look),
                    tooltip: context.tr(LocaleKeys.lookActions),
                    icon: const FormIcon(FormIconName.more, size: 21),
                  ),
                ),
              ),
            ],
          ),
          if (layers.length > 1) ...[
            const SizedBox(height: 10),
            _LayerPills(
              layers: layers,
              selectedId: layer.id,
              ownPhoto: look.isPhoto,
              onSelected: (id) {
                unawaited(HapticFeedback.selectionClick());
                setState(() {
                  _layerId = id;
                  _selectedId = null;
                });
              },
            ),
          ],
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final garment in garments)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _PieceTile(
                      garment: garment,
                      online: widget.online,
                      selected: garment.id == _selectedId,
                      onTap: garment.item == null
                          ? null
                          : () {
                              unawaited(HapticFeedback.selectionClick());
                              setState(
                                () => _selectedId = garment.id == _selectedId
                                    ? null
                                    : garment.id,
                              );
                            },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // A photo look starts without linked pieces, so there is nothing
          // to tap yet.
          if (garments.isNotEmpty)
            AnimatedSwitcher(
              duration: FormTokens.quick,
              child: Text(
                selected?.item?.metadata.name ??
                    context.tr(
                      shown == null
                          ? LocaleKeys.lookFlatHint
                          : LocaleKeys.lookFittingHint,
                    ),
                key: ValueKey(selected?.id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FormTokens.small.copyWith(
                  color: selected == null ? FormTokens.muted : FormTokens.ink,
                ),
              ),
            ),
          if (look.isCombination) ...[
            const SizedBox(height: 18),
            _AddImage(look: look, online: widget.online),
          ],
          if (look.isPhoto) ...[
            const SizedBox(height: 22),
            FoundPieces(look: look, state: widget.state, online: widget.online),
          ],
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (items.isNotEmpty)
                  Text(
                    _headline(context, items),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: FormTokens.heading.copyWith(
                      fontSize: 24,
                      height: 1.25,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(meta, style: FormTokens.small),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    _ownership(context, items, garments.length),
                    style: FormTokens.body,
                  ),
                ],
                if (families.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final family in families)
                        ColorChip(
                          label: context.tr('colorFamilies.$family'),
                          swatch: colorFamilySwatches[family],
                          onTap: () => widget.onOpenStack(ColorStack(family)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _CollectButton(
              filedIn: filedIn,
              onTap: widget.online
                  ? () => showCollectionSheet(context, lookId: look.id)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

const _headlineOrder = [
  'coat',
  'jacket',
  'dress',
  'top',
  'pants',
  'skirt',
  'shoes',
  'bag',
  'hat',
  'scarf',
  'accessory',
];

/// Names the look after its two most defining pieces, outerwear and dresses
/// first, e.g. "Teddyjacke & Tanktop".
String _headline(BuildContext context, List<WardrobeItem> items) {
  int rank(WardrobeItem item) {
    final index = _headlineOrder.indexOf(item.metadata.category);
    return index < 0 ? _headlineOrder.length : index;
  }

  final names = ([...items]..sort((a, b) => rank(a) - rank(b)))
      .take(2)
      .map((item) => item.metadata.name)
      .toList();
  return names.join(' & ');
}

/// How many of the look's pieces are in the closet, and which ones are still
/// on the wish list.
String _ownership(BuildContext context, List<WardrobeItem> items, int total) {
  final owned = items.where((item) => item.state == 'owning').length;
  final wanting = [
    for (final item in items)
      if (item.state == 'wanting') item.metadata.name,
  ];
  final count = owned == total
      ? context.tr(LocaleKeys.lookOwnedAll)
      : owned == 0
      ? context.tr(LocaleKeys.lookOwnedNone)
      : context.tr(
          LocaleKeys.lookOwnedSome,
          namedArgs: {'owned': '$owned', 'total': '$total'},
        );
  if (wanting.isEmpty) return count;
  final names = wanting.length == 1
      ? wanting.single
      : '${wanting.sublist(0, wanting.length - 1).join(', ')} '
            '${context.tr(LocaleKeys.listAnd)} ${wanting.last}';
  final wish = context.tr(
    wanting.length == 1
        ? LocaleKeys.lookWantingOne
        : LocaleKeys.lookWantingMany,
    namedArgs: {'names': names},
  );
  return '$count $wish';
}

/// A piece in the fitting room strip. The selected piece lifts and takes a
/// green outline.
class _PieceTile extends StatelessWidget {
  const _PieceTile({
    required this.garment,
    required this.online,
    required this.selected,
    required this.onTap,
  });

  final LookGarment garment;
  final bool online;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final item = garment.item;
    return Semantics(
      button: true,
      selected: selected,
      label: item?.metadata.name,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedSlide(
          offset: Offset(0, selected ? -0.04 : 0),
          duration: const Duration(milliseconds: 240),
          curve: FormTokens.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: FormTokens.easeOut,
            width: 66,
            height: 82,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: item == null
                  ? FormTokens.field
                  : FormTokens.tileTint(item.id, item.metadata.colors),
              borderRadius: BorderRadius.circular(FormTokens.inputRadius),
              border: Border.all(
                color: selected ? FormTokens.green : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: [
                if (selected)
                  const BoxShadow(
                    color: Color(0x141D281C),
                    offset: Offset(0, 6),
                    blurRadius: 18,
                  ),
              ],
            ),
            child: item == null
                ? null
                : CachedMedia(
                    identity: item.previewIdentity,
                    previewPath: item.previewPath,
                    online: online,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Marks where the selected piece sits on the worn photo, with its name in a
/// label that opens the piece.
/// Pulsing dots on the photo where each piece can be tapped. [points] are in
/// percent of the photo's width and height.
class _TapAreaHints extends StatefulWidget {
  const _TapAreaHints({
    required this.visible,
    required this.points,
    required this.size,
  });

  final bool visible;
  final List<Offset> points;
  final Size size;

  @override
  State<_TapAreaHints> createState() => _TapAreaHintsState();
}

class _TapAreaHintsState extends State<_TapAreaHints>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_TapAreaHints oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) _sync();
  }

  void _sync() {
    if (widget.visible && !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_pulse.repeat());
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dot = 14.0;
    const ring = 52.0;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 320),
        curve: FormTokens.easeOut,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => Stack(
            children: [
              for (var i = 0; i < widget.points.length; i++)
                Positioned(
                  left:
                      widget.points[i].dx / 100 * widget.size.width - ring / 2,
                  top:
                      widget.points[i].dy / 100 * widget.size.height - ring / 2,
                  width: ring,
                  height: ring,
                  // Each dot pops in a beat after the previous one and
                  // breathes slightly out of step, so they feel alive
                  // rather than blinking in unison.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: widget.visible ? 1 : 0),
                    duration: Duration(milliseconds: 650 + i * 90),
                    curve: widget.visible ? Curves.elasticOut : Curves.easeIn,
                    builder: (context, pop, child) =>
                        Transform.scale(scale: pop, child: child),
                    child: _dot((_pulse.value + i * 0.17) % 1, dot, ring),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// One dot at [phase] of its breath: a soft halo swells and fades while
  /// the dot itself gently grows and settles.
  Widget _dot(double phase, double dot, double ring) {
    final halo = Curves.easeOutCubic.transform(phase);
    final breath = 1 + 0.14 * math.sin(phase * math.pi * 2);
    final fade = 1 - phase;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: dot + (ring - dot) * halo,
          height: dot + (ring - dot) * halo,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.5 * fade * fade),
          ),
        ),
        Transform.scale(
          scale: breath,
          child: Container(
            width: dot,
            height: dot,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x401D281C),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PieceMarker extends StatelessWidget {
  const _PieceMarker({
    required this.garment,
    required this.position,
    required this.size,
  });

  final LookGarment? garment;
  final LookItemPosition? position;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final position = this.position;
    final garment = this.garment;
    final visible = position != null && garment?.item != null;
    // The body regions are estimates by category, so the ring stays generous.
    final diameter = position == null
        ? 0.0
        : (position.size * 1.35 / 100 * size.width).clamp(64.0, 150.0);
    final cx = position == null
        ? size.width / 2
        : position.originX / 100 * size.width;
    final cy = position == null
        ? size.height / 2
        : position.originY / 100 * size.height;
    final labelBelow = cy < size.height * 0.62;
    const duration = Duration(milliseconds: 280);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              curve: FormTokens.easeOut,
              child: const ColoredBox(color: Color(0x261D281C)),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: duration,
          curve: FormTokens.easeOut,
          left: cx - diameter / 2,
          top: cy - diameter / 2,
          width: diameter,
          height: diameter,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x331D281C),
                      offset: Offset(0, 4),
                      blurRadius: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: duration,
          curve: FormTokens.easeOut,
          left: 0,
          right: 0,
          top: labelBelow ? cy + diameter / 2 + 10 : null,
          bottom: labelBelow ? null : size.height - cy + diameter / 2 + 10,
          child: Center(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              child: IgnorePointer(
                ignoring: !visible,
                child: GestureDetector(
                  onTap: garment == null
                      ? null
                      : () => context.push('/wardrobe/items/${garment.id}'),
                  child: Container(
                    constraints: BoxConstraints(maxWidth: size.width - 40),
                    padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(
                        FormTokens.chipRadius,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            garment?.item?.metadata.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: FormTokens.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr(LocaleKeys.lookOpenPiece),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: FormTokens.green,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: FormTokens.green,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Files the look into Sammlungen. Empty, it invites with a heart. Once
/// filed, it shows where the look lives, and tapping changes that.
class _CollectButton extends StatelessWidget {
  const _CollectButton({required this.filedIn, required this.onTap});

  final List<LookCollection> filedIn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final filed = filedIn.isNotEmpty;
    final label = filed
        ? filedIn.map((c) => '${c.emoji} ${c.name}').join('  ·  ')
        : context.tr(LocaleKeys.collectionAdd);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                unawaited(HapticFeedback.lightImpact());
                onTap!();
              },
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: AnimatedContainer(
            duration: FormTokens.quick,
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: filed ? FormTokens.selectedTint : FormTokens.field,
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
                  child: FormIcon(
                    filed ? FormIconName.heartFilled : FormIconName.heart,
                    key: ValueKey(filed),
                    size: 18,
                    color: filed ? FormTokens.green : FormTokens.ink,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: filed ? FormTokens.green : FormTokens.ink,
                    ),
                  ),
                ),
                Icon(
                  filed ? Icons.edit_outlined : Icons.add,
                  size: 18,
                  color: filed ? FormTokens.green : FormTokens.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The worn photo at 4:5 in a card-radius frame. [overlay] draws on top at
/// the photo's laid-out size.
class _LookPhoto extends StatelessWidget {
  const _LookPhoto({
    required this.record,
    required this.online,
    this.onTapAt,
    this.overlay,
  });

  final CachedLook record;
  final bool online;

  /// Receives the tap position in percent of the photo's width and height.
  final ValueChanged<Offset>? onTapAt;
  final Widget Function(Size size)? overlay;

  @override
  Widget build(BuildContext context) {
    final assetId = record.look.cardAssetId!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(FormTokens.panelRadius),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: ColoredBox(
          color: FormTokens.lookStage,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTapUp: onTapAt == null
                      ? null
                      : (details) => onTapAt!(
                          Offset(
                            details.localPosition.dx /
                                constraints.maxWidth *
                                100,
                            details.localPosition.dy /
                                constraints.maxHeight *
                                100,
                          ),
                        ),
                  child: CachedMedia(
                    identity: assetId,
                    previewPath: record.previewPath(assetId),
                    online: online,
                    fit: BoxFit.cover,
                  ),
                ),
                ?overlay?.call(constraints.biggest),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _occasionLabel(BuildContext context, String? occasion) =>
    switch (occasion) {
      'night-out' => context.tr(LocaleKeys.composerOccasionNightOut),
      'party' => context.tr(LocaleKeys.composerOccasionParty),
      'casual' => context.tr(LocaleKeys.composerOccasionCasual),
      _ => null,
    };

/// The look's pieces laid out flat at the photo's 4:5, on paper. Tapping a
/// piece highlights it, as tapping it on a photo does.
class _FlatStage extends StatelessWidget {
  const _FlatStage({
    required this.garments,
    required this.online,
    required this.selectedId,
    required this.onGarmentTap,
  });

  final List<LookGarment> garments;
  final bool online;
  final String? selectedId;
  final ValueChanged<String> onGarmentTap;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(FormTokens.panelRadius),
    child: AspectRatio(
      aspectRatio: 4 / 5,
      child: ColoredBox(
        color: FormTokens.flatLayPaper,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: _FlatEntrance(
              builder: (entrance) => FlatLayBoard(
                garments: garments,
                online: online,
                entrance: entrance,
                selectedId: selectedId,
                onGarmentTap: (id) {
                  unawaited(HapticFeedback.selectionClick());
                  onGarmentTap(id);
                },
              ),
              count: garments.length,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Runs the pieces' rise into place once, when the flat lay first shows.
class _FlatEntrance extends StatefulWidget {
  const _FlatEntrance({required this.builder, required this.count});

  final Widget Function(Animation<double> entrance) builder;
  final int count;

  @override
  State<_FlatEntrance> createState() => _FlatEntranceState();
}

class _FlatEntranceState extends State<_FlatEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: FlatLayBoard.entranceDuration(widget.count),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      unawaited(_controller.forward());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}

/// An image of a combination that is still being made, or failed: the
/// pieces under a drifting sheen, or a way to try again.
class _ImageInProgress extends StatelessWidget {
  const _ImageInProgress({
    required this.look,
    required this.garments,
    required this.online,
    required this.onRetry,
  });

  final Look look;
  final List<LookGarment> garments;
  final bool online;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = look.state == 'failed';
    return ClipRRect(
      borderRadius: BorderRadius.circular(FormTokens.panelRadius),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: ColoredBox(
          color: FormTokens.lookStage,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: failed ? 0.25 : 0.45,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: FlatLayBoard(
                      garments: garments,
                      online: online,
                      arrive: true,
                    ),
                  ),
                ),
              ),
              if (!failed) const DevelopingSheen(active: true),
              Align(
                alignment: const Alignment(0, 0.78),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 10,
                    children: [
                      Text(
                        context.tr(
                          failed
                              ? LocaleKeys.lookImageFailed
                              : LocaleKeys.lookImageDeveloping,
                        ),
                        textAlign: TextAlign.center,
                        style: FormTokens.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (failed && onRetry != null)
                        FilledButton(
                          onPressed: online ? onRetry : null,
                          child: Text(context.tr(LocaleKeys.retry)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Switches between a look's photo, its images and its flat lay. The
/// selected pill slides under the label as a green tint.
class _LayerPills extends StatelessWidget {
  const _LayerPills({
    required this.layers,
    required this.selectedId,
    required this.ownPhoto,
    required this.onSelected,
  });

  final List<_Layer> layers;
  final String selectedId;

  /// The look is a photo the user wore it in, so its photo is "Worn".
  final bool ownPhoto;
  final ValueChanged<String> onSelected;

  String _label(BuildContext context, _Layer layer) {
    final look = layer.record?.look;
    return context.tr(switch (look) {
      null => LocaleKeys.lookLayerFlat,
      _ when ownPhoto && look.isPhoto => LocaleKeys.lookLayerWorn,
      _ when look.isTryOn => LocaleKeys.lookLayerTryOn,
      _ => LocaleKeys.lookLayerInspiration,
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: Row(
      spacing: 6,
      children: [
        for (final layer in layers)
          Semantics(
            button: true,
            selected: layer.id == selectedId,
            child: GestureDetector(
              onTap: () => onSelected(layer.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: FormTokens.easeOut,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: layer.id == selectedId
                      ? FormTokens.selectedTint
                      : FormTokens.pill,
                  borderRadius: BorderRadius.circular(FormTokens.chipRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    if (layer.record?.look case final look? when look.isActive)
                      const SizedBox.square(
                        dimension: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    else if (layer.record?.look.state == 'failed')
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: FormTokens.danger,
                      ),
                    Text(
                      _label(context, layer),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: layer.id == selectedId
                            ? FormTokens.green
                            : FormTokens.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Puts an image on top of a combination: on a photo of the user, or as an
/// AI inspiration. The combination stays as it is either way.
class _AddImage extends StatelessWidget {
  const _AddImage({required this.look, required this.online});

  final Look look;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final credits = context.watch<CreditsCubit>().state;
    final cost = credits?.metered == false
        ? null
        : context.tr(
            LocaleKeys.lookCostBadge,
            namedArgs: {'cost': '$lookCreditCost'},
          );
    Widget option(String mode, IconData icon, String label) => Expanded(
      child: Material(
        color: FormTokens.field,
        borderRadius: BorderRadius.circular(FormTokens.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: online
              ? () {
                  unawaited(HapticFeedback.lightImpact());
                  unawaited(addLookImage(context, look, mode: mode));
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Opacity(
              opacity: online ? 1 : 0.45,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Icon(icon, size: 22, color: FormTokens.green),
                  Text(
                    label,
                    style: FormTokens.body.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (cost != null)
                    Text(
                      cost,
                      style: FormTokens.small.copyWith(
                        color: FormTokens.coinInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            context.tr(LocaleKeys.lookAddImage),
            style: FormTokens.small,
          ),
        ),
        Row(
          spacing: 10,
          children: [
            option(
              'try-on',
              Icons.person_outline,
              context.tr(LocaleKeys.lookTryOn),
            ),
            option(
              'inspiration',
              Icons.auto_awesome_outlined,
              context.tr(LocaleKeys.lookInspiration),
            ),
          ],
        ),
      ],
    );
  }
}
