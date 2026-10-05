import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';

/// Planned outfits from the composer as a swipe deck: right renders the
/// outfit, left skips it. Only the outfits swiped right cost credits.
class LookProposalsPage extends StatelessWidget {
  const LookProposalsPage({required this.quality, this.request, super.key});

  final String quality;

  /// The composer's propose body, reused for "more proposals".
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

  void _decide(Look look, {required bool pick}) {
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
    final deck = state.deck;
    final total = state.proposals?.where((l) => l.state != 'failed').length;
    final top = deck.firstOrNull;
    final topReady = top?.state == 'proposed';
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
          child: Column(
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
                  if (total != null && total > 0 && !state.finished)
                    Text(
                      '${(total - deck.length + 1).clamp(1, total)} / $total',
                      style: FormTokens.small.copyWith(color: FormTokens.ink),
                    ),
                ],
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
                child: state.finished
                    ? _Finished(state: state)
                    : state.proposing || state.proposals == null
                    ? const _PlanningCard()
                    : _SwipeDeck(
                        key: _deck,
                        deck: deck,
                        onDecide: _decide,
                        cardBuilder: (look) => look.state == 'proposed'
                            ? _ProposalCard(
                                look: look,
                                itemsById: itemsById,
                                online: !wardrobe.stale,
                              )
                            : const _PlanningCard(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top card follows the finger, tilts, and flies off past a threshold.
/// The next card waits slightly smaller behind it.
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
  late final AnimationController _motion = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => setState(() => _dx = _motion.value));
  double _dx = 0;
  double _width = 1;

  Look? get _top => widget.deck.firstOrNull;
  bool get _draggable => _top?.state == 'proposed';

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  /// Throws the top card off to one side, e.g. from the buttons.
  Future<void> fling({required bool right}) async {
    final look = _top;
    if (look == null || !_draggable || _motion.isAnimating) return;
    await _motion.animateTo(
      (right ? 1 : -1) * _width * 1.4,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeIn,
    );
    if (!mounted) return;
    widget.onDecide(look, pick: right);
    _motion.value = 0;
  }

  void _release(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (_dx.abs() > _width * 0.32 || velocity.abs() > 900) {
      unawaited(fling(right: (_dx.abs() > 1 ? _dx : velocity) > 0));
    } else {
      unawaited(
        _motion.animateTo(
          0,
          duration: const Duration(milliseconds: 380),
          curve: Curves.elasticOut,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = _top;
    if (top == null) return const SizedBox.shrink();
    final next = widget.deck.elementAtOrNull(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final progress = (_dx / (_width * 0.32)).clamp(-1.0, 1.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (next != null)
              Positioned.fill(
                child: Transform.scale(
                  // Grows into place as the top card leaves.
                  scale: 0.93 + 0.07 * progress.abs(),
                  alignment: Alignment.bottomCenter,
                  child: Opacity(
                    opacity: 0.6 + 0.4 * progress.abs(),
                    child: widget.cardBuilder(next),
                  ),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                onHorizontalDragUpdate: _draggable
                    ? (details) {
                        _motion.stop();
                        setState(() => _dx += details.delta.dx);
                      }
                    : null,
                onHorizontalDragEnd: _draggable ? _release : null,
                child: Transform.translate(
                  offset: Offset(_dx, _dx.abs() * 0.06),
                  child: Transform.rotate(
                    angle: _dx / _width * 0.22,
                    alignment: Alignment.bottomCenter,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: KeyedSubtree(
                            key: ValueKey(top.id),
                            child: widget.cardBuilder(top),
                          ),
                        ),
                        Positioned(
                          top: 22,
                          left: 22,
                          child: _Stamp(
                            label: context.tr(LocaleKeys.proposalsRender),
                            color: FormTokens.green,
                            angle: -0.2,
                            visible: progress.clamp(0.0, 1.0),
                          ),
                        ),
                        Positioned(
                          top: 22,
                          right: 22,
                          child: _Stamp(
                            label: context.tr(LocaleKeys.proposalsSkipOne),
                            color: FormTokens.muted,
                            angle: 0.2,
                            visible: (-progress).clamp(0.0, 1.0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
  Widget build(BuildContext context) => Opacity(
    opacity: visible,
    child: Transform.rotate(
      angle: angle,
      child: Transform.scale(
        scale: 0.8 + 0.2 * visible,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
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
  );
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FormTokens.flatLayPaper,
      borderRadius: BorderRadius.circular(FormTokens.panelRadius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A26351D),
          blurRadius: 18,
          offset: Offset(0, 8),
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
  });

  final Look look;
  final Map<String, WardrobeItem> itemsById;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final reasons = [
      for (final reason in look.reasons ?? const <LookReason>[])
        ?_reasonChip(context, reason, itemsById),
    ];
    // The piece the outfit was built around stands out in the flat lay.
    final anchorId = (look.reasons ?? const <LookReason>[])
        .where((reason) => reason.itemId != null)
        .firstOrNull
        ?.itemId;
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: FlatLayBoard(
                garments: lookGarments(look, itemsById),
                online: online,
                selectedId: anchorId,
                // The pieces drop onto the card one after another.
                arrive: true,
              ),
            ),
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: reasons),
          ],
        ],
      ),
    );
  }
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
      color: FormTokens.surface,
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

/// Stands in for an outfit that is still being planned: pieces bob on the
/// card while the line below says what FORM is doing.
class _PlanningCard extends StatefulWidget {
  const _PlanningCard();

  @override
  State<_PlanningCard> createState() => _PlanningCardState();
}

class _PlanningCardState extends State<_PlanningCard>
    with SingleTickerProviderStateMixin {
  late final _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();
  late final Timer _ticker;
  int _step = 0;

  static const List<String> _steps = [
    LocaleKeys.proposalsPlanningPieces,
    LocaleKeys.proposalsPlanningScene,
    LocaleKeys.proposalsPlanningFinish,
  ];

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 1800),
      (_) => setState(() => _step = (_step + 1) % _steps.length),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CardSurface(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _bob,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < 3; index++)
                Transform.translate(
                  offset: Offset(
                    0,
                    -10 *
                        math.max(
                          0,
                          math.sin((_bob.value - index * 0.18) * 2 * math.pi),
                        ),
                  ),
                  child: Container(
                    width: 58,
                    height: 72,
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: FormTokens.field,
                      borderRadius: BorderRadius.circular(
                        FormTokens.cardRadius,
                      ),
                    ),
                    child: const Center(
                      child: FormIcon(
                        FormIconName.top,
                        size: 26,
                        color: FormTokens.emptyIcon,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            context.tr(_steps[_step]),
            key: ValueKey(_step),
            style: FormTokens.small,
          ),
        ),
      ],
    ),
  );
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
      IconButton.filledTonal(
        onPressed: enabled ? onSkip : null,
        tooltip: context.tr(LocaleKeys.proposalsSkipOne),
        iconSize: 26,
        padding: const EdgeInsets.all(14),
        icon: const Icon(Icons.close),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: FilledButton.icon(
          onPressed: enabled ? onPick : null,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text(
            lookCostLabel(
              context,
              context.tr(LocaleKeys.proposalsRender),
              context.watch<CreditsCubit>().state,
            ),
          ),
        ),
      ),
    ],
  );
}

class _Finished extends StatelessWidget {
  const _Finished({required this.state});

  final LookProposalsState state;

  @override
  Widget build(BuildContext context) {
    final picked = state.picked.length;
    final failed =
        state.proposals!.isNotEmpty &&
        state.proposals!.every((look) => look.state == 'failed');
    return _CardSurface(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              picked > 0 ? Icons.auto_awesome : Icons.style_outlined,
              size: 40,
              color: FormTokens.green,
            ),
            const SizedBox(height: 14),
            Text(
              failed
                  ? context.tr(LocaleKeys.proposalsFailed)
                  : picked > 0
                  ? context.plural(LocaleKeys.proposalsPicked, picked)
                  : context.tr(LocaleKeys.proposalsNonePicked),
              textAlign: TextAlign.center,
              style: FormTokens.body,
            ),
          ],
        ),
      ),
    );
  }
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
