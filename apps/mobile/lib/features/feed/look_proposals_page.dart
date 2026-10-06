import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/look_proposals_cubit.dart';
import 'package:form_mobile/features/feed/occasion_tile.dart';
import 'package:form_mobile/features/settings/credits_cubit.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_cubit.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:go_router/go_router.dart';

/// Planned outfits from the composer as a swipe deck. Right renders the
/// outfit, left shows the next one. Tapping a piece keeps it for the next
/// outfits, tapping again rules it out, so a look can be built across swipes.
class LookProposalsPage extends StatelessWidget {
  const LookProposalsPage({required this.quality, this.request, super.key});

  final String quality;

  /// The composer's propose body, reused for every further proposal.
  final Map<String, dynamic>? request;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => LookProposalsCubit(
      context.read<LookRepository>(),
      quality: quality,
      request: request,
    ),
    child: const _ProposalsView(),
  );
}

class _ProposalsView extends StatefulWidget {
  const _ProposalsView();

  @override
  State<_ProposalsView> createState() => _ProposalsViewState();
}

class _ProposalsViewState extends State<_ProposalsView> {
  final _deck = GlobalKey<_SwipeDeckState>();

  /// The piece on the top card whose actions are open.
  String? _selected;

  void _decide(Look look, {required bool pick}) {
    setState(() => _selected = null);
    final cubit = context.read<LookProposalsCubit>();
    if (pick) {
      unawaited(HapticFeedback.mediumImpact());
      unawaited(cubit.pick(look.id));
    } else {
      unawaited(HapticFeedback.selectionClick());
      cubit.skip(look.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LookProposalsCubit>().state;
    final cubit = context.read<LookProposalsCubit>();
    final wardrobe = context.watch<WardrobeCubit>().state;
    final itemsById = <String, WardrobeItem>{
      for (final cached in wardrobe.items ?? const <CachedItem>[])
        cached.item.id: cached.item,
    };
    final online = !wardrobe.stale;
    final deck = state.deck;
    final topReady = deck.firstOrNull?.state == 'proposed';
    return FormSheet(
      title: context.tr(LocaleKeys.proposalsTitle),
      scrollable: false,
      footer: state.finished
          ? _FinishedActions(
              picked: state.picked.length,
              canPropose: cubit.request != null,
              proposing: state.proposing,
            )
          : _DeckActions(
              enabled: topReady,
              onSkip: () => _deck.currentState?.fling(right: false),
              onPick: () => _deck.currentState?.fling(right: true),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: constraints.maxHeight,
          child: state.finished
              ? _Finished(state: state, itemsById: itemsById, online: online)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr(LocaleKeys.proposalsHint),
                            style: FormTokens.small,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _Progress(
                          seen: state.decided,
                          total: maxSessionProposals,
                        ),
                      ],
                    ),
                    _YourLook(
                      marks: state.marks,
                      itemsById: itemsById,
                      online: online,
                      onTap: cubit.unmark,
                    ),
                    if (state.failure != null) ...[
                      const SizedBox(height: 10),
                      FormNotice(
                        text: apiFailureText(context, state.failure!),
                        error: true,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Expanded(
                      child: deck.isEmpty
                          ? _PlanningCard(building: state.kept.isNotEmpty)
                          : _SwipeDeck(
                              key: _deck,
                              deck: deck,
                              onDecide: _decide,
                              cardBuilder: (look) => look.state == 'proposed'
                                  ? _ProposalCard(
                                      look: look,
                                      itemsById: itemsById,
                                      online: online,
                                      marks: state.marks,
                                      // Only the top card takes taps.
                                      selectedId: look == deck.first
                                          ? _selected
                                          : null,
                                      onPieceTap: (id) => setState(
                                        () => _selected = _selected == id
                                            ? null
                                            : id,
                                      ),
                                      onKeep: (id) {
                                        unawaited(
                                          HapticFeedback.mediumImpact(),
                                        );
                                        setState(() => _selected = null);
                                        unawaited(
                                          cubit.keep(id, onLookId: look.id),
                                        );
                                      },
                                      onSwap: (id) {
                                        unawaited(
                                          HapticFeedback.lightImpact(),
                                        );
                                        setState(() => _selected = null);
                                        unawaited(
                                          cubit.swap(id, onLookId: look.id),
                                        );
                                      },
                                    )
                                  : _PlanningCard(
                                      building: state.kept.isNotEmpty,
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

/// One dot per outfit of the session, filling as outfits are decided.
class _Progress extends StatelessWidget {
  const _Progress({required this.seen, required this.total});

  final int seen;
  final int total;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var index = 0; index < total; index++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: FormTokens.easeOut,
          margin: const EdgeInsets.only(left: 3),
          width: index == seen ? 14 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: index <= seen ? FormTokens.green : FormTokens.line,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );
}

/// Every marked piece in the order it was marked: kept ones with a green pin,
/// swapped-out ones faded behind a red cross. Tapping one drops its mark.
class _YourLook extends StatelessWidget {
  const _YourLook({
    required this.marks,
    required this.itemsById,
    required this.online,
    required this.onTap,
  });

  final Map<String, PieceMark> marks;
  final Map<String, WardrobeItem> itemsById;
  final bool online;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final marked = [
      for (final entry in marks.entries)
        if (itemsById[entry.key] case final item?)
          (item: item, mark: entry.value),
    ];
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: FormTokens.easeOut,
      alignment: Alignment.topCenter,
      child: marked.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Text(
                    context.tr(LocaleKeys.proposalsYourLook),
                    style: FormTokens.small.copyWith(
                      color: FormTokens.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        children: [
                          for (final entry in marked)
                            _MarkThumb(
                              key: ValueKey(entry.item.id),
                              item: entry.item,
                              kept: entry.mark == PieceMark.keep,
                              online: online,
                              onTap: () => onTap(entry.item.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MarkThumb extends StatelessWidget {
  const _MarkThumb({
    required this.item,
    required this.kept,
    required this.online,
    required this.onTap,
    super.key,
  });

  final WardrobeItem item;
  final bool kept;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 420),
    curve: FormTokens.pop,
    builder: (context, value, child) =>
        Transform.scale(scale: value, child: child),
    child: Semantics(
      button: true,
      label: item.metadata.name,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 8, top: 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: kept ? FormTokens.selectedTint : FormTokens.dangerTint,
                  borderRadius: BorderRadius.circular(FormTokens.inputRadius),
                ),
                child: Opacity(
                  opacity: kept ? 1 : 0.45,
                  child: CachedMedia(
                    identity: item.previewIdentity,
                    previewPath: item.previewPath,
                    online: online,
                  ),
                ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: kept ? FormTokens.green : FormTokens.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: FormTokens.surface, width: 1.5),
                  ),
                  child: Icon(
                    kept ? Icons.push_pin : Icons.close,
                    size: 10,
                    color: FormTokens.surface,
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

/// The top card follows the finger, tilts, and flies off past a threshold or
/// springs back. The next card waits slightly smaller behind it.
class _SwipeDeck extends StatefulWidget {
  const _SwipeDeck({
    required this.deck,
    required this.onDecide,
    required this.cardBuilder,
    super.key,
  });

  final List<Look> deck;
  final void Function(Look look, {required bool pick}) onDecide;
  final Widget Function(Look look) cardBuilder;

  @override
  State<_SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<_SwipeDeck>
    with SingleTickerProviderStateMixin {
  // The card's horizontal offset. Drags write it directly and releases
  // animate it, so a spring back always starts where the finger let go.
  late final AnimationController _dx = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => setState(() {}));
  double _width = 1;
  bool _flinging = false;

  Look? get _top => widget.deck.firstOrNull;
  bool get _draggable => _top?.state == 'proposed' && !_flinging;
  double get _threshold => _width * 0.3;

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  /// Throws the top card off to one side, from a swipe or the buttons.
  Future<void> fling({required bool right, double velocity = 0}) async {
    final look = _top;
    if (look == null || look.state != 'proposed' || _flinging) return;
    _flinging = true;
    final target = (right ? 1 : -1) * _width * 1.5;
    final distance = (target - _dx.value).abs();
    await _dx.animateTo(
      target,
      duration: Duration(
        milliseconds: (distance / math.max(velocity.abs(), 2400) * 1000)
            .clamp(140, 320)
            .round(),
      ),
      curve: Curves.easeOut,
    );
    if (!mounted) return;
    widget.onDecide(look, pick: right);
    _dx.value = 0;
    _flinging = false;
  }

  void _release(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final offset = _dx.value;
    final flicked = velocity.abs() > 800 && velocity.sign == offset.sign;
    if (offset.abs() > _threshold || flicked) {
      unawaited(fling(right: offset > 0, velocity: velocity));
      return;
    }
    unawaited(
      _dx.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 420, damping: 24),
          offset,
          0,
          velocity,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = _top;
    if (top == null) return const SizedBox.shrink();
    final next = widget.deck.elementAtOrNull(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final dx = _dx.value;
        final progress = (dx / _threshold).clamp(-1.0, 1.0);
        // Both cards share one widget shape and are keyed by look, so the
        // next card keeps its state when it moves to the top instead of
        // being rebuilt and dropping its pieces in a second time.
        Widget card(Look look, {required bool isTop}) => Positioned.fill(
          key: ValueKey(look.id),
          child: IgnorePointer(
            ignoring: !isTop,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: isTop && _draggable
                  ? (_) => _dx.stop()
                  : null,
              onHorizontalDragUpdate: isTop && _draggable
                  ? (details) => _dx.value += details.delta.dx
                  : null,
              onHorizontalDragEnd: isTop && _draggable ? _release : null,
              child: Transform.translate(
                offset: isTop
                    ? Offset(dx, dx.abs() * 0.05)
                    : Offset(0, 14 * (1 - progress.abs())),
                child: Transform.rotate(
                  angle: isTop ? dx / _width * 0.2 : 0,
                  alignment: const Alignment(0, 2),
                  child: Transform.scale(
                    // The next card grows into place as the top one leaves.
                    scale: isTop ? 1 : 0.94 + 0.06 * progress.abs(),
                    child: Stack(
                      children: [
                        Positioned.fill(child: widget.cardBuilder(look)),
                        // Tints the card toward the decision it is about to
                        // make.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  FormTokens.panelRadius,
                                ),
                                color:
                                    (progress > 0
                                            ? FormTokens.green
                                            : FormTokens.ink)
                                        .withValues(
                                          alpha: isTop
                                              ? 0.07 * progress.abs()
                                              : 0,
                                        ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 22,
                          left: 22,
                          child: _Stamp(
                            label: context.tr(LocaleKeys.proposalsRender),
                            color: FormTokens.green,
                            angle: -0.2,
                            visible: isTop ? progress.clamp(0.0, 1.0) : 0,
                          ),
                        ),
                        Positioned(
                          top: 22,
                          right: 22,
                          child: _Stamp(
                            label: context.tr(LocaleKeys.proposalsSkipStamp),
                            color: FormTokens.ink,
                            angle: 0.2,
                            visible: isTop ? (-progress).clamp(0.0, 1.0) : 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (next != null) card(next, isTop: false),
            card(top, isTop: true),
          ],
        );
      },
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.angle,
    required this.visible,
  });

  final String label;
  final Color color;
  final double angle;
  final double visible;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Opacity(
      opacity: visible,
      child: Transform.rotate(
        angle: angle,
        child: Transform.scale(
          scale: 0.7 + 0.3 * visible,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FormTokens.surface.withValues(alpha: 0.85),
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label.toUpperCase(),
              style: FormTokens.title.copyWith(
                color: color,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FormTokens.surface,
      borderRadius: BorderRadius.circular(FormTokens.panelRadius),
      border: Border.all(color: FormTokens.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F26351D),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.look,
    required this.itemsById,
    required this.online,
    required this.marks,
    required this.selectedId,
    required this.onPieceTap,
    required this.onKeep,
    required this.onSwap,
  });

  final Look look;
  final Map<String, WardrobeItem> itemsById;
  final bool online;
  final Map<String, PieceMark> marks;
  final String? selectedId;
  final ValueChanged<String> onPieceTap;
  final ValueChanged<String> onKeep;
  final ValueChanged<String> onSwap;

  @override
  Widget build(BuildContext context) {
    final reasons = [
      for (final reason in look.reasons ?? const <LookReason>[])
        ?_reasonChip(context, reason, itemsById),
    ];
    final selected = look.wardrobeItemIds.contains(selectedId)
        ? selectedId
        : null;
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: FlatLayBoard(
                garments: lookGarments(look, itemsById),
                online: online,
                selectedId: selected,
                // New and swapped-in pieces drop onto the card.
                arrive: true,
                onGarmentTap: (id) {
                  unawaited(HapticFeedback.selectionClick());
                  onPieceTap(id);
                },
                imageBuilder: (item) => _MarkedPiece(
                  kept: marks[item.id] == PieceMark.keep,
                  leftOut: marks[item.id] == PieceMark.exclude,
                  child: CachedMedia(
                    identity: item.previewIdentity,
                    previewPath: item.previewPath,
                    online: online,
                  ),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, child: child),
            ),
            child: selected == null
                ? Column(
                    key: const ValueKey('reasons'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.tr(LocaleKeys.proposalsTapHint),
                        textAlign: TextAlign.center,
                        style: FormTokens.small,
                      ),
                      if (reasons.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 6, runSpacing: 6, children: reasons),
                      ],
                    ],
                  )
                : _PieceActions(
                    key: ValueKey(selected),
                    name: itemsById[selected]?.metadata.name ?? '',
                    kept: marks[selected] == PieceMark.keep,
                    leftOut: marks[selected] == PieceMark.exclude,
                    onKeep: () => onKeep(selected),
                    onSwap: () => onSwap(selected),
                  ),
          ),
        ],
      ),
    );
  }
}

/// What can happen to the selected piece: keep it for the next outfits, or
/// leave it out of them. This card stays as it is either way.
class _PieceActions extends StatelessWidget {
  const _PieceActions({
    required this.name,
    required this.kept,
    required this.leftOut,
    required this.onKeep,
    required this.onSwap,
    super.key,
  });

  final String name;
  final bool kept;
  final bool leftOut;
  final VoidCallback onKeep;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FormTokens.small.copyWith(
          color: FormTokens.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: leftOut ? null : onSwap,
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              label: Text(
                context.tr(
                  leftOut
                      ? LocaleKeys.proposalsLeftOut
                      : LocaleKeys.proposalsSwap,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: kept ? null : onKeep,
              icon: const Icon(Icons.push_pin_outlined, size: 18),
              label: Text(
                context.tr(
                  kept ? LocaleKeys.proposalsKept : LocaleKeys.proposalsKeep,
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// A piece the user kept gets a pin badge. One left out fades back: it stays
/// on this card but not in the next outfits.
class _MarkedPiece extends StatelessWidget {
  const _MarkedPiece({
    required this.kept,
    required this.leftOut,
    required this.child,
  });

  final bool kept;
  final bool leftOut;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    fit: StackFit.expand,
    children: [
      AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: leftOut ? 0.3 : 1,
        child: child,
      ),
      Positioned(
        top: 0,
        right: 0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 320),
          curve: FormTokens.pop,
          scale: kept ? 1 : 0,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: FormTokens.green,
              shape: BoxShape.circle,
              border: Border.all(color: FormTokens.surface, width: 2),
            ),
            child: const Icon(
              Icons.push_pin,
              size: 13,
              color: FormTokens.surface,
            ),
          ),
        ),
      ),
    ],
  );
}

/// A short, factual reason chip. Null for kinds this app does not know.
Widget? _reasonChip(
  BuildContext context,
  LookReason reason,
  Map<String, WardrobeItem> itemsById,
) {
  String piece() =>
      itemsById[reason.itemId]?.metadata.name ??
      context.tr(LocaleKeys.proposalsReasonPieceFallback);
  final content = switch (reason.kind) {
    'new-piece' => (
      Icons.fiber_new_outlined,
      context.tr(LocaleKeys.proposalsReasonNew, namedArgs: {'piece': piece()}),
    ),
    'never-styled' => (
      Icons.auto_awesome_outlined,
      context.tr(
        LocaleKeys.proposalsReasonNever,
        namedArgs: {'piece': piece()},
      ),
    ),
    'rarely-styled' => (
      Icons.history,
      context.tr(
        LocaleKeys.proposalsReasonRarely,
        namedArgs: {'piece': piece()},
      ),
    ),
    'your-pick' => (
      Icons.favorite_border,
      context.plural(LocaleKeys.proposalsReasonPick, reason.itemIds.length),
    ),
    'occasion' => switch (occasionPresets
        .where((preset) => preset.value == reason.occasion)
        .firstOrNull) {
      final preset? => (
        Icons.event_outlined,
        context.tr(
          LocaleKeys.proposalsReasonOccasion,
          namedArgs: {'occasion': context.tr(preset.label)},
        ),
      ),
      null => null,
    },
    'fresh' => (Icons.shuffle, context.tr(LocaleKeys.proposalsReasonFresh)),
    _ => null,
  };
  if (content == null) return null;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: FormTokens.flatLayPaper,
      borderRadius: BorderRadius.circular(FormTokens.chipRadius),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(content.$1, size: 14, color: FormTokens.green),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            content.$2,
            style: FormTokens.small.copyWith(color: FormTokens.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// Stands in for an outfit that is still being planned: ghost pieces where
/// the flat lay will be, with a slow light passing over them.
class _PlanningCard extends StatefulWidget {
  const _PlanningCard({this.building = false});

  /// Kept pieces exist, so the next outfit is built around them.
  final bool building;

  @override
  State<_PlanningCard> createState() => _PlanningCardState();
}

class _PlanningCardState extends State<_PlanningCard>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  // Ghost pieces roughly where a flat lay puts top, jacket, bottoms, shoes.
  // Each breathes and drifts at its own unrelated pace, so the card never
  // settles into a loop the eye can pick up.
  static const List<
    ({double x, double y, double w, double h, double pace, double phase})
  >
  _ghosts = [
    (x: 0.08, y: 0.06, w: 0.42, h: 0.34, pace: 0.83, phase: 0),
    (x: 0.54, y: 0.1, w: 0.38, h: 0.3, pace: 1.17, phase: 2.1),
    (x: 0.14, y: 0.46, w: 0.34, h: 0.46, pace: 0.61, phase: 4.3),
    (x: 0.6, y: 0.66, w: 0.26, h: 0.2, pace: 1.39, phase: 1.2),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => setState(() => _elapsed = elapsed));
    unawaited(_ticker.start());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _elapsed.inMilliseconds / 1000;
    return _CardSurface(
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  for (final ghost in _ghosts)
                    Positioned(
                      left: ghost.x * constraints.maxWidth,
                      top: ghost.y * constraints.maxHeight,
                      width: ghost.w * constraints.maxWidth,
                      height: ghost.h * constraints.maxHeight,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          3 * math.sin(t * ghost.pace * 0.9 + ghost.phase),
                        ),
                        child: Opacity(
                          opacity:
                              0.55 +
                              0.45 *
                                  (0.5 +
                                      0.5 *
                                          math.sin(
                                            t * ghost.pace + ghost.phase,
                                          )),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: FormTokens.flatLayPaper,
                              borderRadius: BorderRadius.circular(
                                FormTokens.panelRadius,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              widget.building
                  ? LocaleKeys.proposalsPlanningBuilding
                  : LocaleKeys.proposalsPlanningNext,
            ),
            style: FormTokens.small,
          ),
        ],
      ),
    );
  }
}

class _DeckActions extends StatelessWidget {
  const _DeckActions({
    required this.enabled,
    required this.onSkip,
    required this.onPick,
  });

  final bool enabled;
  final VoidCallback onSkip;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // Skipping is the light action, generating the one that costs.
      TextButton.icon(
        onPressed: enabled ? onSkip : null,
        style: TextButton.styleFrom(foregroundColor: FormTokens.muted),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text(context.tr(LocaleKeys.proposalsSkipOne)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton(
          onPressed: enabled ? onPick : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 56),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              lookCostLabel(
                context,
                context.tr(LocaleKeys.proposalsRender),
                context.watch<CreditsCubit>().state,
              ),
              maxLines: 1,
            ),
          ),
        ),
      ),
    ],
  );
}

/// The session's end: picked outfits fan out like cards dealt onto a table.
class _Finished extends StatelessWidget {
  const _Finished({
    required this.state,
    required this.itemsById,
    required this.online,
  });

  final LookProposalsState state;
  final Map<String, WardrobeItem> itemsById;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final picked = [
      for (final look in state.proposals ?? const <Look>[])
        if (state.picked.contains(look.id)) look,
    ];
    final failed =
        picked.isEmpty &&
        state.decided == 0 &&
        (state.proposals?.isNotEmpty ?? false);
    final shown = picked.length > 3
        ? picked.sublist(picked.length - 3)
        : picked;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 250,
          child: shown.isEmpty
              ? Center(
                  child: _Dealt(
                    index: 0,
                    angle: 0,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: const BoxDecoration(
                        color: FormTokens.flatLayPaper,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        failed
                            ? Icons.cloud_off_outlined
                            : Icons.style_outlined,
                        size: 48,
                        color: FormTokens.green,
                      ),
                    ),
                  ),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final (index, look) in shown.indexed)
                      _Dealt(
                        index: index,
                        angle: (index - (shown.length - 1) / 2) * 0.16,
                        offset: (index - (shown.length - 1) / 2) * 70,
                        child: SizedBox(
                          width: 150,
                          height: 200,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: FormTokens.surface,
                              borderRadius: BorderRadius.circular(
                                FormTokens.cardRadius,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x2626351D),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: FlatLayBoard(
                                garments: lookGarments(look, itemsById),
                                online: online,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 28),
        Text(
          failed
              ? context.tr(LocaleKeys.proposalsFailedTitle)
              : picked.isNotEmpty
              ? context.plural(LocaleKeys.proposalsPicked, picked.length)
              : context.tr(LocaleKeys.proposalsNonePicked),
          textAlign: TextAlign.center,
          style: FormTokens.heading,
        ),
        const SizedBox(height: 10),
        Text(
          failed
              ? context.tr(LocaleKeys.proposalsFailed)
              : picked.isNotEmpty
              ? context.tr(LocaleKeys.proposalsPickedBody)
              : context.tr(LocaleKeys.proposalsNonePickedBody),
          textAlign: TextAlign.center,
          style: FormTokens.body.copyWith(color: FormTokens.muted),
        ),
      ],
    );
  }
}

/// Deals its child in: drops, rotates into place and settles with a pop.
class _Dealt extends StatelessWidget {
  const _Dealt({
    required this.index,
    required this.angle,
    required this.child,
    this.offset = 0,
  });

  final int index;
  final double angle;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 520 + index * 140),
    curve: Interval(index * 0.2, 1, curve: FormTokens.pop),
    builder: (context, value, child) => Transform.translate(
      offset: Offset(offset * value, (1 - value) * 60),
      child: Transform.rotate(
        angle: angle * value,
        child: Opacity(opacity: value.clamp(0, 1), child: child),
      ),
    ),
    child: child,
  );
}

class _FinishedActions extends StatelessWidget {
  const _FinishedActions({
    required this.picked,
    required this.canPropose,
    required this.proposing,
  });

  final int picked;
  final bool canPropose;
  final bool proposing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (canPropose) ...[
        Expanded(
          child: OutlinedButton(
            onPressed: proposing
                ? null
                : () => unawaited(context.read<LookProposalsCubit>().more()),
            child: Text(context.tr(LocaleKeys.proposalsMore)),
          ),
        ),
        const SizedBox(width: 12),
      ],
      Expanded(
        child: FilledButton(
          onPressed: () => context.go('/feed'),
          child: Text(
            context.tr(
              picked > 0 ? LocaleKeys.proposalsDone : LocaleKeys.proposalsSkip,
            ),
          ),
        ),
      ),
    ],
  );
}
