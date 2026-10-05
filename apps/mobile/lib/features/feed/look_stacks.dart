import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/look_card.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/look_repository.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';

/// Swatch colours for the colour families in `wardrobe_filter.dart`.
const Map<String, Color> colorFamilySwatches = {
  'black': Color(0xFF26282A),
  'white': Color(0xFFFBFAF6),
  'gray': Color(0xFF9C9F9A),
  'beige': Color(0xFFDCCBAE),
  'brown': Color(0xFF7B5638),
  'blue': Color(0xFF3F5F8A),
  'green': Color(0xFF5E7A55),
  'yellow': Color(0xFFE2C25A),
  'orange': Color(0xFFD9814A),
  'red': Color(0xFFA8383A),
  'purple': Color(0xFF7A5C93),
  'pink': Color(0xFFE3A3B4),
};

/// A colour as a pill with its swatch. Look and piece pages share it, and
/// [onTap] opens the looks in that colour.
class ColorChip extends StatelessWidget {
  const ColorChip({
    required this.label,
    required this.swatch,
    this.onTap,
    super.key,
  });

  final String label;
  final Color? swatch;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 36),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.fromLTRB(8, 6, 13, 6),
      backgroundColor: FormTokens.pill,
      foregroundColor: FormTokens.ink,
      disabledBackgroundColor: FormTokens.pill,
      disabledForegroundColor: FormTokens.ink,
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 13),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorDot(color: swatch, size: 16),
        const SizedBox(width: 7),
        Text(label),
      ],
    ),
  );
}

/// A round colour swatch with a hairline so white stays visible on paper.
class ColorDot extends StatelessWidget {
  const ColorDot({required this.color, this.size = 18, super.key});
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color ?? FormTokens.field,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x1F1D281C)),
    ),
  );
}

/// A pressable stack: it fans out once when first built, staggered by
/// [index] on the first screen, opens wider while held and springs back on
/// release. [builder] gets the current spread, 0 closed, 1 at rest, above 1
/// while pressed.
class StackPressable extends StatefulWidget {
  const StackPressable({
    required this.builder,
    required this.onTap,
    required this.semanticLabel,
    this.index = 0,
    super.key,
  });

  final Widget Function(BuildContext context, double spread) builder;
  final VoidCallback onTap;
  final String semanticLabel;
  final int index;

  @override
  State<StackPressable> createState() => _StackPressableState();
}

class _StackPressableState extends State<StackPressable>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 520),
  );
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance.status != AnimationStatus.dismissed) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
      return;
    }
    // Only the first screen staggers; stacks scrolled into view later fan
    // out right away.
    _delay = Timer(
      Duration(milliseconds: widget.index < 6 ? 80 + 70 * widget.index : 0),
      () => _entrance.forward(),
    );
  }

  @override
  void dispose() {
    _delay?.cancel();
    _entrance.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.semanticLabel,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) => _press.reverse(),
      onTapCancel: _press.reverse,
      onTap: () {
        unawaited(HapticFeedback.selectionClick());
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_entrance, _press]),
        builder: (context, _) {
          final entrance = FormTokens.pop.transform(_entrance.value);
          final press = _press.status == AnimationStatus.reverse
              ? FormTokens.pop.transform(_press.value)
              : FormTokens.easeOut.transform(_press.value);
          // Before the entrance the prints lie squared on a pile, visible,
          // so a stack never looks missing while it waits.
          return Transform.scale(
            scale: 1 - press * 0.035,
            child: widget.builder(context, entrance + press * 0.35),
          );
        },
      ),
    ),
  );
}

/// Up to three look photos fanned like prints dropped on a table. The first
/// look lies on top. [spread] comes from [StackPressable].
///
/// With [developingFace], looks that are still being made join the fan as
/// prints that show that face under a drifting sheen, so a new look visibly
/// lands on its stack.
class PhotoFan extends StatelessWidget {
  const PhotoFan({
    required this.looks,
    required this.online,
    required this.photoSize,
    required this.spread,
    this.angle = 0.11,
    this.offset = 0.36,
    this.developingFace,
    super.key,
  });

  final List<CachedLook> looks;
  final Widget Function(CachedLook record)? developingFace;
  final bool online;
  final Size photoSize;
  final double spread;

  /// Rotation of the outer photos in radians, at a spread of 1.
  final double angle;

  /// Sideways shift of the outer photos as a share of the photo width.
  final double offset;

  @override
  Widget build(BuildContext context) {
    final photos = looks
        .where(
          (r) =>
              r.look.assetId != null ||
              (developingFace != null && r.look.isActive),
        )
        .take(3)
        .toList();
    // Back to front: right, left, then the top print.
    final layers = <(int, double)>[
      if (photos.length > 2) (2, 1),
      if (photos.length > 1) (1, -1),
      (0, 0),
    ];
    return SizedBox(
      width: photoSize.width * (1 + offset * 2) + 16,
      height: photoSize.height + 24,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (final (index, side) in layers)
            Transform.translate(
              offset: Offset(
                side * photoSize.width * offset * spread,
                side == 0 ? 0 : 6 * spread,
              ),
              child: Transform.rotate(
                angle: side * angle * spread,
                child: _Print(
                  record: index < photos.length ? photos[index] : null,
                  online: online,
                  size: photoSize,
                  elevated: side == 0,
                  developingFace: developingFace,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Print extends StatelessWidget {
  const _Print({
    required this.record,
    required this.online,
    required this.size,
    required this.elevated,
    this.developingFace,
  });

  final CachedLook? record;
  final bool online;
  final Size size;
  final bool elevated;
  final Widget Function(CachedLook record)? developingFace;

  @override
  Widget build(BuildContext context) {
    final assetId = record?.look.assetId;
    const frame = 2.5;
    final radius = size.width > 120 ? 14.0 : 10.0;
    // A white frame around the photo, which is clipped to the frame's inner
    // radius so its corners follow the frame.
    return Container(
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.all(frame),
      decoration: BoxDecoration(
        color: FormTokens.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF1D281C,
            ).withValues(alpha: elevated ? 0.16 : 0.09),
            blurRadius: elevated ? 22 : 12,
            offset: Offset(0, elevated ? 10 : 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - frame),
        child: ColoredBox(
          color: FormTokens.flatLayPaper,
          child: record != null && record!.look.isActive && assetId == null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // Faded like an underexposed print until the photo is in.
                    if (developingFace case final face?)
                      Opacity(
                        opacity: 0.4,
                        child: Center(child: face(record!)),
                      ),
                    const DevelopingSheen(active: true),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: size.height * 0.08,
                      child: const Center(child: _DevelopingBadge()),
                    ),
                  ],
                )
              : assetId == null
              ? const SizedBox.expand()
              : CachedMedia(
                  identity: assetId,
                  previewPath: record!.previewPath(assetId),
                  online: online,
                  fit: BoxFit.cover,
                  entrance: MediaEntrance.fade,
                ),
        ),
      ),
    );
  }
}

/// A piece's stack: its catalog cut-out on paper in front, with the looks it
/// appears in fanned out behind.
class PiecePile extends StatelessWidget {
  const PiecePile({
    required this.item,
    required this.looks,
    required this.online,
    required this.spread,
    super.key,
  });

  final WardrobeItem item;
  final List<CachedLook> looks;
  final bool online;
  final double spread;

  static const _photo = Size(76, 95);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    height: 128,
    child: Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Transform.translate(
          offset: Offset(0, -10 * spread),
          child: PhotoFan(
            looks: looks,
            online: online,
            photoSize: _photo,
            spread: spread * 0.9,
            angle: 0.16,
            offset: 0.3,
          ),
        ),
        Transform.translate(
          offset: Offset(0, 22 + 4 * spread),
          child: Transform.rotate(
            angle: -0.04 * spread,
            child: Container(
              width: 84,
              height: 84,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: FormTokens.tileTint(item.id, item.metadata.colors),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x261D281C),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: CachedMedia(
                identity: item.previewIdentity,
                previewPath: item.previewPath,
                online: online,
                entrance: MediaEntrance.fade,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A colour's stack: its looks fanned behind a round swatch.
class ColorPile extends StatelessWidget {
  const ColorPile({
    required this.family,
    required this.looks,
    required this.online,
    required this.spread,
    super.key,
  });

  final String family;
  final List<CachedLook> looks;
  final bool online;
  final double spread;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 116,
    height: 112,
    child: Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        PhotoFan(
          looks: looks,
          online: online,
          photoSize: const Size(64, 80),
          spread: spread,
          angle: 0.14,
          offset: 0.32,
        ),
        Positioned(
          bottom: -2,
          child: Transform.scale(
            scale: 0.85 + 0.15 * spread.clamp(0, 1.2),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorFamilySwatches[family],
                shape: BoxShape.circle,
                border: Border.all(color: FormTokens.surface, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2E1D281C),
                    blurRadius: 12,
                    offset: Offset(0, 5),
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

/// The looks of one stack as large cards to leaf through sideways. The
/// neighbours peek in, shrunk and turned slightly, and straighten as they
/// arrive. [onPage] reports the visible card's index. Pulling a card down
/// past its top drags the cards along and, far enough, calls [onDismiss].
class LookPager extends StatefulWidget {
  const LookPager({
    required this.itemCount,
    required this.itemBuilder,
    required this.onPage,
    required this.onDismiss,
    this.topInset = 0,
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final ValueChanged<int> onPage;
  final VoidCallback onDismiss;

  /// Space above each card, for a header the cards scroll under.
  final double topInset;

  @override
  State<LookPager> createState() => _LookPagerState();
}

class _LookPagerState extends State<LookPager>
    with SingleTickerProviderStateMixin {
  static const _dismissDistance = 110.0;

  final _controller = PageController(viewportFraction: 0.86);

  /// How far the cards are pulled down past the top.
  late final _pull = AnimationController.unbounded(vsync: this);
  var _dismissed = false;

  @override
  void dispose() {
    _controller.dispose();
    _pull.dispose();
    super.dispose();
  }

  // Only the card's own vertical scroll counts, not the piece carousels in
  // it. Clamping physics reports the pull past the top as overscroll.
  bool _onScroll(ScrollNotification notification) {
    if (_dismissed ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    switch (notification) {
      case OverscrollNotification(:final overscroll, dragDetails: _?)
          when overscroll < 0:
        _setPull(_pull.value - overscroll * 0.6);
      case ScrollUpdateNotification(:final scrollDelta?, dragDetails: _?)
          when _pull.value > 0 && scrollDelta > 0:
        _setPull(math.max(0, _pull.value - scrollDelta));
      case ScrollEndNotification(:final dragDetails):
        final fling = (dragDetails?.primaryVelocity ?? 0) > 700;
        if (_pull.value >= _dismissDistance || (fling && _pull.value > 20)) {
          _dismissed = true;
          widget.onDismiss();
        } else if (_pull.value > 0) {
          unawaited(
            _pull.animateTo(
              0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : FormTokens.quick,
              curve: FormTokens.easeOut,
            ),
          );
        }
    }
    return false;
  }

  void _setPull(double value) {
    if ((_pull.value < _dismissDistance) != (value < _dismissDistance)) {
      unawaited(HapticFeedback.selectionClick());
    }
    _pull.value = value;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pull,
    builder: (context, child) => Transform.translate(
      offset: Offset(0, _pull.value),
      child: Opacity(
        opacity: (1 - _pull.value / 500).clamp(0.0, 1.0),
        child: child,
      ),
    ),
    child: PageView.builder(
      controller: _controller,
      itemCount: widget.itemCount,
      onPageChanged: (index) {
        unawaited(HapticFeedback.selectionClick());
        widget.onPage(index);
      },
      itemBuilder: (context, index) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final page =
              _controller.hasClients && _controller.position.haveDimensions
              ? _controller.page!
              : _controller.initialPage.toDouble();
          final delta = (index - page).clamp(-1.0, 1.0);
          final distance = delta.abs();
          return Opacity(
            opacity: 1 - distance * 0.35,
            child: Transform.translate(
              offset: Offset(0, distance * 18),
              child: Transform.rotate(
                angle: delta * 0.05,
                child: Transform.scale(
                  scale: 1 - distance * 0.07,
                  child: child,
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: SingleChildScrollView(
              // Always scrollable, so short cards can be pulled down too.
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.only(top: widget.topInset),
              child: widget.itemBuilder(context, index),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A box sliver that rebuilds with how far it has moved from where it rests:
/// 0 at rest, 1 after scrolling [distance] pixels up, negative while pulled
/// down past the top. It reads its laid-out position rather than the scroll
/// offset, so a refresh control opening or closing above it moves the value
/// smoothly instead of jumping.
class SliverScrollProgress extends StatelessWidget {
  const SliverScrollProgress({
    required this.distance,
    required this.builder,
    super.key,
  });

  final double distance;
  final Widget Function(BuildContext context, double progress) builder;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final top =
          constraints.viewportMainAxisExtent -
          constraints.remainingPaintExtent -
          constraints.scrollOffset;
      final progress = (constraints.precedingScrollExtent - top) / distance;
      return SliverToBoxAdapter(child: builder(context, progress));
    },
  );
}

/// A pulsing dot and "developing" on a dark pill, over a print still being
/// made.
class _DevelopingBadge extends StatelessWidget {
  const _DevelopingBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
    decoration: BoxDecoration(
      color: FormTokens.toast,
      borderRadius: BorderRadius.circular(FormTokens.chipRadius),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 7,
      children: [
        const _PulsingDot(),
        Text(
          context.tr(LocaleKeys.lookDevelopingBadge),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

/// A small dot that breathes while rings ripple out from it, like a
/// recording light.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0.3;
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 14,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final ring = FormTokens.easeOut.transform(t);
        final breath = 0.5 - 0.5 * math.cos(2 * math.pi * t);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 6 + 8 * ring,
              height: 6 + 8 * ring,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FormTokens.selectedTint.withValues(
                  alpha: 0.55 * (1 - ring),
                ),
              ),
            ),
            Transform.scale(
              scale: 0.85 + 0.15 * breath,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: FormTokens.selectedTint,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
