import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_cubit.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/feed_presentation.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/feed/look_positions.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/look.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/media_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/form_icon.dart';
import 'package:go_router/go_router.dart';

class LookCard extends StatefulWidget {
  const LookCard({
    required this.record,
    required this.state,
    required this.garments,
    required this.online,
    required this.onRetry,
    required this.onDelete,
    required this.onShare,
    required this.onMenu,
    super.key,
  });

  final CachedLook record;
  final FeedState state;
  final List<LookGarment> garments;
  final bool online;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  /// Shares the representation the card currently shows.
  /// Receives the share button's global rect, which anchors the share sheet.
  final ValueChanged<Rect> onShare;
  final VoidCallback onMenu;

  @override
  State<LookCard> createState() => _LookCardState();
}

/// A look in progress and a ready look share one layout, so the card keeps
/// its size while it develops. It stays in the developing state until the
/// worn image is decoded, then crossfades to it.
class _LookCardState extends State<LookCard> {
  late bool _imageReady = widget.record.look.isReady;

  Look get look => widget.record.look;

  @override
  void didUpdateWidget(LookCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (look.isReady && !oldWidget.record.look.isReady && !_imageReady) {
      unawaited(_prepareImage());
    }
  }

  Future<void> _prepareImage() async {
    final assetId = look.assetId;
    try {
      if (assetId != null) {
        final file = await context.read<MediaRepository>().load(
          assetId,
          previewPath: widget.record.previewPath(assetId),
          online: widget.online,
        );
        if (file != null && mounted) {
          await precacheImage(FileImage(file), context);
        }
      }
    } finally {
      if (mounted) setState(() => _imageReady = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (look.state == 'failed') {
      return _FailedLookCard(
        garments: widget.garments,
        moderated: look.failureCategory == 'moderation',
        online: widget.online,
        onRetry: widget.onRetry,
        onDelete: widget.onDelete,
      );
    }
    final developing = !look.isReady || !_imageReady;
    final online = widget.online;
    final state = widget.state;
    final view = developing
        ? LookFeedView.flat
        : state.views[look.id] ?? LookFeedView.worn;
    final revealed = state.revealed.contains(look.id);
    final liked = state.liked[look.id] ?? false;
    final saved = state.saved[look.id] ?? false;
    final positions = lookItemPositions(
      widget.garments.map((g) => g.item?.metadata.category ?? 'top').toList(),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: FormTokens.chrome,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: _Settling(
                developing: developing,
                child: Row(
                  children: [
                    _LookViewSwitch(
                      selected: view,
                      onSelected: (value) =>
                          context.read<FeedCubit>().setLookView(look.id, value),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: widget.onMenu,
                      tooltip: context.tr(LocaleKeys.lookActions),
                      icon: const FormIcon(FormIconName.more),
                    ),
                  ],
                ),
              ),
            ),
            AspectRatio(
              aspectRatio: 4 / 5,
              child: _LookStage(
                record: widget.record,
                view: view,
                developing: developing,
                garments: widget.garments,
                positions: positions,
                revealed: revealed,
                online: online,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The glyphs carry their own inset inside the 44px targets.
                  // The row offsets those so the heart's and bookmark's
                  // strokes line up with the caption's edges.
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _Settling(
                      developing: developing,
                      child: Row(
                        children: [
                          _FooterAction(
                            onPressed: online
                                ? () => context.read<FeedCubit>().toggleMark(
                                    look.id,
                                    liked: true,
                                  )
                                : null,
                            tooltip: context.tr(LocaleKeys.lookLike),
                            selected: liked,
                            icon: FormIcon(
                              liked
                                  ? FormIconName.heartFilled
                                  : FormIconName.heart,
                              color: liked ? FormTokens.liked : FormTokens.ink,
                            ),
                          ),
                          Builder(
                            builder: (buttonContext) => _FooterAction(
                              onPressed: () {
                                final box =
                                    buttonContext.findRenderObject()!
                                        as RenderBox;
                                widget.onShare(
                                  box.localToGlobal(Offset.zero) & box.size,
                                );
                              },
                              tooltip: context.tr(LocaleKeys.lookShare),
                              icon: const FormIcon(
                                FormIconName.share,
                                color: FormTokens.ink,
                              ),
                            ),
                          ),
                          const Spacer(),
                          _FooterAction(
                            onPressed: online
                                ? () => context.read<FeedCubit>().toggleMark(
                                    look.id,
                                    liked: false,
                                  )
                                : null,
                            tooltip: context.tr(LocaleKeys.lookSave),
                            selected: saved,
                            icon: FormIcon(
                              saved
                                  ? FormIconName.bookmarkFilled
                                  : FormIconName.bookmark,
                              color: FormTokens.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 320),
                          curve: FormTokens.easeOut,
                          alignment: Alignment.topCenter,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topLeft,
                              children: [
                                ...previous,
                                ?current,
                              ],
                            ),
                            child: developing
                                ? _DevelopingCaption(
                                    key: const ValueKey('developing'),
                                    look: look,
                                    hasGarments: widget.garments.isNotEmpty,
                                  )
                                : _LookCaption(
                                    key: const ValueKey('caption'),
                                    mood: look.concept?.mood,
                                    caption: lookCaption(look),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          lookDateText(context, look.createdAt),
                          style: FormTokens.small,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims and disables controls that only apply to a finished look.
class _Settling extends StatelessWidget {
  const _Settling({required this.developing, required this.child});

  final bool developing;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: developing,
    child: AnimatedOpacity(
      opacity: developing ? 0.35 : 1,
      duration: const Duration(milliseconds: 320),
      curve: FormTokens.easeOut,
      child: child,
    ),
  );
}

/// Progress copy in the caption's place, styled like the caption: the step in
/// bold, followed inline by what happens next.
class _DevelopingCaption extends StatelessWidget {
  const _DevelopingCaption({
    required this.look,
    required this.hasGarments,
    super.key,
  });

  final Look look;
  final bool hasGarments;

  @override
  Widget build(BuildContext context) {
    final generating = look.state == 'generating' || look.isReady;
    final title = context.tr(
      generating
          ? LocaleKeys.lookGeneratingTitle
          : LocaleKeys.lookPlanningTitle,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$title ',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: FormTokens.ink,
            ),
          ),
          TextSpan(
            text: context.tr(
              generating
                  ? LocaleKeys.lookGeneratingBody
                  : hasGarments
                  ? LocaleKeys.lookPlanningWithItems
                  : LocaleKeys.lookPlanningBody,
            ),
          ),
        ],
      ),
      style: FormTokens.small.copyWith(fontSize: 13, height: 1.5),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
    this.selected = false,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final Widget icon;
  final bool selected;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    isSelected: selected,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    icon: icon,
  );
}

/// Mood in bold, followed inline by the caption. Collapsed to two lines;
/// tapping expands it, like the PWA's `.look-caption`.
class _LookCaption extends StatefulWidget {
  const _LookCaption({required this.mood, required this.caption, super.key});

  final String? mood;
  final String caption;

  @override
  State<_LookCaption> createState() => _LookCaptionState();
}

class _LookCaptionState extends State<_LookCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    if (mood == null && widget.caption.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedSize(
        duration: FormTokens.quick,
        curve: FormTokens.easeOut,
        alignment: Alignment.topCenter,
        child: Text.rich(
          TextSpan(
            children: [
              if (mood != null)
                TextSpan(
                  text: widget.caption.isEmpty ? mood : '$mood ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: FormTokens.ink,
                  ),
                ),
              TextSpan(text: widget.caption),
            ],
          ),
          style: FormTokens.small.copyWith(fontSize: 13, height: 1.5),
          maxLines: _expanded ? null : 2,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Compact worn/flat pill switch, matching the PWA's `.look-view-switch`.
/// Both segments share the wider label's width so the pill can slide.
class _LookViewSwitch extends StatelessWidget {
  const _LookViewSwitch({required this.selected, required this.onSelected});

  final LookFeedView selected;
  final ValueChanged<LookFeedView> onSelected;

  static const _duration = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FormTokens.switchTrack,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: IntrinsicWidth(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                duration: _duration,
                curve: FormTokens.easeOut,
                alignment: selected == LookFeedView.flat
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: FormTokens.switchSelected,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0B27371B),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final (view, label) in [
                  (LookFeedView.worn, LocaleKeys.lookViewWorn),
                  (LookFeedView.flat, LocaleKeys.lookViewFlat),
                ])
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: view == selected,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(view),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 40),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          child: AnimatedDefaultTextStyle(
                            duration: _duration,
                            curve: FormTokens.easeOut,
                            style: TextStyle(
                              fontSize: 13,
                              color: view == selected
                                  ? FormTokens.flatLayInk
                                  : FormTokens.switchInk,
                            ),
                            child: Text(context.tr(label)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// The image area of a look. Both views stay mounted so switching never
/// reloads media: the two views crossfade, and the flat lay pieces
/// rise in each time it is shown. While [developing], the flat lay fills in
/// piece by piece under a slow sheen.
class _LookStage extends StatefulWidget {
  const _LookStage({
    required this.record,
    required this.view,
    required this.developing,
    required this.garments,
    required this.positions,
    required this.revealed,
    required this.online,
  });

  final CachedLook record;
  final LookFeedView view;
  final bool developing;
  final List<LookGarment> garments;
  final List<LookItemPosition> positions;
  final bool revealed;
  final bool online;

  @override
  State<_LookStage> createState() => _LookStageState();
}

class _LookStageState extends State<_LookStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: FlatLayBoard.entranceDuration(widget.garments.length),
    // A developing look already shows its flat lay, which must stay at rest
    // while it fades out for the worn image.
    value: widget.view == LookFeedView.flat ? 1 : 0,
  );

  @override
  void didUpdateWidget(_LookStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entrance.duration = FlatLayBoard.entranceDuration(widget.garments.length);
    if (widget.view == LookFeedView.flat &&
        oldWidget.view != LookFeedView.flat) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _entrance.value = 1;
      } else {
        unawaited(_entrance.forward(from: 0));
      }
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.record.look;
    final worn = widget.view == LookFeedView.worn;
    void openItem(String id) => context.push('/wardrobe/items/$id');
    return ColoredBox(
      color: FormTokens.lookStage,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: worn,
            child: AnimatedOpacity(
              opacity: worn ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              curve: FormTokens.easeOut,
              child: FlatLayBoard(
                garments: widget.garments,
                online: widget.online,
                entrance: _entrance,
                arrive: widget.developing,
                onGarmentTap: widget.developing ? null : openItem,
              ),
            ),
          ),
          IgnorePointer(
            ignoring: !worn,
            child: AnimatedOpacity(
              opacity: worn ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: FormTokens.easeOut,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (look.assetId != null && !widget.developing)
                    Semantics(
                      button: true,
                      label: context.tr(LocaleKeys.lookRevealPieces),
                      child: GestureDetector(
                        onTap: () {
                          _RevealHint.seen = true;
                          context.read<FeedCubit>().toggleRevealed(look.id);
                        },
                        // Only the worn photo can be dark; the flat lay and
                        // the card chrome keep the page's dark icons.
                        child: MediaStatusBarRegion(
                          identity: look.assetId!,
                          previewPath: widget.record.previewPath(look.assetId!),
                          online: widget.online,
                          enabled: worn,
                          child: CachedMedia(
                            identity: look.assetId!,
                            previewPath: widget.record.previewPath(
                              look.assetId!,
                            ),
                            online: widget.online,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  _WornGarments(
                    garments: widget.garments,
                    positions: widget.positions,
                    revealed: widget.revealed,
                    online: widget.online,
                    onGarmentTap: openItem,
                  ),
                  if (look.assetId != null &&
                      !widget.developing &&
                      widget.garments.isNotEmpty)
                    _RevealHint(visible: !widget.revealed),
                  if (look.isTryOn)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(
                            FormTokens.chipRadius,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.checkroom_rounded,
                                size: 14,
                                color: FormTokens.green,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                context.tr(LocaleKeys.tryOnBadge),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: FormTokens.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _DevelopingSheen(active: widget.developing),
        ],
      ),
    );
  }
}

class _FailedLookCard extends StatelessWidget {
  const _FailedLookCard({
    required this.garments,
    required this.moderated,
    required this.online,
    required this.onRetry,
    required this.onDelete,
  });

  final List<LookGarment> garments;

  /// The image model's safety filter rejected the image, which says more than
  /// a generic failure: the photo or pieces need changing, not a retry alone.
  final bool moderated;
  final bool online;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => FormPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (garments.isNotEmpty)
          FlatLayBoard(garments: garments, online: online),
        const SizedBox(height: 16),
        Text(
          context.tr(LocaleKeys.lookFailedTitle),
          style: FormTokens.heading.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
            moderated
                ? LocaleKeys.lookFailedModeration
                : LocaleKeys.lookFailedBody,
          ),
          style: FormTokens.body,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: online ? onRetry : null,
          child: Text(context.tr(LocaleKeys.lookRetry)),
        ),
        TextButton(
          onPressed: online ? onDelete : null,
          child: Text(context.tr(LocaleKeys.lookDelete)),
        ),
      ],
    ),
  );
}

/// Soft bands of light that drift across the stage while a look develops,
/// then fade away once the worn image is in.
class _DevelopingSheen extends StatefulWidget {
  const _DevelopingSheen({required this.active});

  final bool active;

  @override
  State<_DevelopingSheen> createState() => _DevelopingSheenState();
}

class _DevelopingSheenState extends State<_DevelopingSheen>
    with SingleTickerProviderStateMixin {
  // One long cycle holds several passes at a steady pace while the brightness
  // swells on its own rhythm, so no two passes in a row look alike and the
  // loop point never shows.
  static const _passes = 7;
  static const _swells = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_DevelopingSheen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
    // Once inactive the sheen keeps drifting under the fade-out.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: widget.active ? 1 : 0,
      duration: const Duration(milliseconds: 480),
      curve: FormTokens.easeOut,
      onEnd: () {
        if (!widget.active) _controller.stop();
      },
      // Keeps the per-frame repaint to the sheen, so the pieces beneath it
      // are not redrawn with every step.
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final cycle = _controller.value;
            final phase = cycle * _passes % 1;
            final swell = 0.5 - 0.5 * math.cos(2 * math.pi * cycle * _swells);
            final peak = 0.2 + 0.16 * swell;
            // The gradient repeats every (4, 5) alignment units, and one pass
            // moves it by exactly that, so passes join without a jump.
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(4 * (phase - 1), 5 * (phase - 1)),
                  end: Alignment(4 * phase, 5 * phase),
                  tileMode: TileMode.repeated,
                  stops: const [0.3, 0.5, 0.7],
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: peak),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// Veils the worn photo and moves each garment from its place on the body
/// into an inset grid, matching the PWA's `.look-items` reveal. Closing plays
/// the stagger in reverse so pieces settle back in the opposite order.
class _WornGarments extends StatefulWidget {
  const _WornGarments({
    required this.garments,
    required this.positions,
    required this.revealed,
    required this.online,
    required this.onGarmentTap,
  });

  final List<LookGarment> garments;
  final List<LookItemPosition> positions;
  final bool revealed;
  final bool online;
  final ValueChanged<String> onGarmentTap;

  @override
  State<_WornGarments> createState() => _WornGarmentsState();
}

class _WornGarmentsState extends State<_WornGarments>
    with SingleTickerProviderStateMixin {
  static const _travel = 460;
  static const _stagger = 30;
  static const _fade = 180;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: widget.revealed ? 1 : 0,
  );

  Duration get _duration => Duration(
    milliseconds:
        _travel + _stagger * (widget.positions.length - 1).clamp(0, 12),
  );

  @override
  void didUpdateWidget(_WornGarments oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _duration;
    if (widget.revealed != oldWidget.revealed) {
      if (widget.revealed) {
        unawaited(_controller.forward());
      } else {
        unawaited(_controller.reverse());
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Fades the veil in over [_fade], ahead of the garments, so the photo is
  /// already dimmed while the pieces travel. Closing clears it last.
  double get _veil {
    final total = _controller.duration!.inMilliseconds;
    return Interval(
      0,
      (_fade / total).clamp(0, 1),
      curve: FormTokens.easeOut,
    ).transform(_controller.value);
  }

  Animation<double> _curveFor(LookItemPosition position) {
    final total = _controller.duration!.inMilliseconds;
    final start = position.order * _stagger / total;
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(
        start,
        (start + _travel / total).clamp(0, 1),
        curve: FormTokens.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.isDismissed) return const SizedBox.shrink();
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.76 * _veil),
                  ),
                ),
              ),
              for (var index = 0; index < widget.garments.length; index++)
                if (index < widget.positions.length)
                  _garment(
                    widget.garments[index],
                    widget.positions[index],
                    width,
                    height,
                  ),
            ],
          );
        },
      );
    },
  );

  Widget _garment(
    LookGarment garment,
    LookItemPosition position,
    double width,
    double height,
  ) {
    final t = _curveFor(position).value;
    final size = position.size / 100 * width;
    final x = lerpDouble(position.originX, position.x, t)! / 100 * width;
    final y = lerpDouble(position.originY, position.y, t)! / 100 * height;
    final item = garment.item;
    return Positioned(
      left: x - size / 2,
      top: y - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        ignoring: !widget.revealed || item == null,
        child: Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.scale(
            scale: lerpDouble(position.originScale, 1, t),
            child: PressableGarment(
              onTap: () => widget.onGarmentTap(garment.id),
              child: item == null
                  ? const SizedBox.shrink()
                  : CachedMedia(
                      identity: item.previewIdentity,
                      previewPath: item.previewPath,
                      online: widget.online,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-time pill on the worn photo saying it can be tapped to show the
/// pieces. Hides for the rest of the session once any photo was tapped.
class _RevealHint extends StatelessWidget {
  const _RevealHint({required this.visible});

  static bool seen = false;

  final bool visible;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    bottom: 14,
    child: IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: visible && !seen ? 1 : 0,
          duration: FormTokens.quick,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(FormTokens.chipRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                context.tr(LocaleKeys.lookRevealPieces),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FormTokens.green,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
