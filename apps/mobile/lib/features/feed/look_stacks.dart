import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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
/// arrive. [onPage] reports the visible card's index.
class LookPager extends StatefulWidget {
  const LookPager({
    required this.itemCount,
    required this.itemBuilder,
    required this.onPage,
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final ValueChanged<int> onPage;

  @override
  State<LookPager> createState() => _LookPagerState();
}

class _LookPagerState extends State<LookPager> {
  final _controller = PageController(viewportFraction: 0.86);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView.builder(
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
              child: Transform.scale(scale: 1 - distance * 0.07, child: child),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: widget.itemBuilder(context, index),
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

/// The Looks screen's invitation to create: the user's own pieces drift as a
/// soft, blurred cloud with the plus in its middle. Tapping gathers every
/// piece into the plus before [onCreate] runs, as if FORM picked them up.
class WardrobeCloud extends StatefulWidget {
  const WardrobeCloud({
    required this.items,
    required this.online,
    required this.label,
    required this.onCreate,
    super.key,
  });

  final List<WardrobeItem> items;
  final bool online;
  final String label;
  final VoidCallback onCreate;

  static const height = 132.0;

  @override
  State<WardrobeCloud> createState() => _WardrobeCloudState();
}

/// Where one piece floats: its resting point as a share of the cloud's size,
/// size, tilt, and the phase and angular speeds (rad/s) of its drift.
typedef _Float = ({
  Offset at,
  double size,
  double tilt,
  double phase,
  double speedX,
  double speedY,
});

class _WardrobeCloudState extends State<WardrobeCloud>
    with TickerProviderStateMixin {
  // Seconds since the drift started. Continuous time keeps the motion from
  // looping visibly, unlike a repeating controller.
  final _drift = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(
    (elapsed) => _drift.value = elapsed.inMicroseconds / 1e6,
  );
  // 0 = pieces at rest, 1 = all inside the plus. A press pulls them part of
  // the way in, release finishes the pull, cancel lets them drift back.
  late final AnimationController _gather = AnimationController(vsync: this);
  bool _pressed = false;
  bool _opening = false;
  late List<_Float> _floats = _scatter(widget.items.length);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      unawaited(_ticker.start());
    }
  }

  @override
  void didUpdateWidget(WardrobeCloud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _floats = _scatter(widget.items.length);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _drift.dispose();
    _gather.dispose();
    super.dispose();
  }

  /// Spreads [count] pieces over two loose rows with a fixed seed, so the
  /// cloud keeps its shape between builds.
  static List<_Float> _scatter(int count) {
    final random = math.Random(7);
    final perRow = (count / 2).ceil();
    return [
      for (var i = 0; i < count; i++)
        (
          at: Offset(
            0.06 +
                0.88 *
                    ((i % perRow) + 0.5 + (random.nextDouble() - 0.5) * 0.6) /
                    perRow,
            (i < perRow ? 0.32 : 0.7) + (random.nextDouble() - 0.5) * 0.16,
          ),
          size: 46 + random.nextDouble() * 22,
          tilt: (random.nextDouble() - 0.5) * 0.7,
          phase: random.nextDouble() * 2 * math.pi,
          speedX: 0.18 + random.nextDouble() * 0.16,
          speedY: 0.14 + random.nextDouble() * 0.16,
        ),
    ];
  }

  void _press() {
    if (_opening) return;
    setState(() => _pressed = true);
    unawaited(HapticFeedback.selectionClick());
    if (MediaQuery.disableAnimationsOf(context)) return;
    unawaited(
      _gather.animateTo(
        0.28,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _cancel() {
    if (_opening) return;
    setState(() => _pressed = false);
    unawaited(HapticFeedback.selectionClick());
    unawaited(
      _gather.animateBack(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
      ),
    );
  }

  Future<void> _create() async {
    if (_opening) return;
    _opening = true;
    setState(() => _pressed = false);
    unawaited(HapticFeedback.lightImpact());
    if (!MediaQuery.disableAnimationsOf(context)) {
      // Shorter when the press already pulled the pieces most of the way.
      final remaining = 1 - _gather.value.clamp(0.0, 1.0);
      await _gather.animateTo(
        1,
        duration: Duration(milliseconds: (240 * remaining).round() + 60),
        curve: Curves.easeInCubic,
      );
    }
    if (!mounted) return;
    // A firmer thud as the pieces land inside the plus.
    unawaited(HapticFeedback.mediumImpact());
    widget.onCreate();
    // Let the composer cover the cloud before it scatters again.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _gather.value = 0;
    _opening = false;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapCancel: _cancel,
      onTap: _create,
      child: SizedBox(
        height: WardrobeCloud.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final center = size.center(Offset.zero);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRect(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_drift, _gather]),
                        builder: (context, _) => Stack(
                          children: [
                            for (final (i, item) in widget.items.indexed)
                              _piece(item, _floats[i], size, center),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: AnimatedBuilder(
                    animation: _gather,
                    builder: (context, child) => Transform.scale(
                      scale:
                          (_pressed ? 0.92 : 1) +
                          math.sin(_gather.value * math.pi) * 0.14,
                      child: child,
                    ),
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: FormTokens.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: FormTokens.paper.withValues(alpha: 0.6),
                            blurRadius: 18,
                            spreadRadius: 4,
                          ),
                          const BoxShadow(
                            color: Color(0x401D281C),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _piece(WardrobeItem item, _Float float, Size size, Offset center) {
    // Two sines at unrelated speeds per axis, so no piece retraces its path.
    final s = _drift.value;
    final x = s * float.speedX + float.phase;
    final y = s * float.speedY + float.phase * 1.7;
    final rest = Offset(
      float.at.dx * size.width + math.sin(x) * 5 + math.sin(x * 2.3) * 2,
      float.at.dy * size.height + math.cos(y) * 4 + math.sin(y * 1.9) * 2,
    );
    final gather = _gather.value;
    final at = Offset.lerp(rest, center, gather)!;
    final side = float.size * (1 - gather * 0.75);
    // 1 at the button, 0 towards the sides: pieces near the plus blur and
    // fade so it stands out, the outer ones stay crisp. Measured from the
    // resting point, so the blur stays constant while a piece drifts.
    // Impeller renders a changing blur sigma in visible steps.
    final focus =
        1 -
        math
            .sqrt(
              math.pow((float.at.dx - 0.5) / 0.4, 2) +
                  math.pow((float.at.dy - 0.5) / 0.6, 2),
            )
            .clamp(0.0, 1.0);
    final sigma = 4 * focus * focus;
    return Positioned(
      left: (at.dx - side / 2).clamp(0, math.max(0, size.width - side)),
      top: (at.dy - side / 2).clamp(0, math.max(0, size.height - side)),
      width: side,
      height: side,
      child: ColorFiltered(
        colorFilter: _wash(1 - (1 - focus * 0.4) * (1 - gather * 0.6)),
        child: ImageFiltered(
          enabled: sigma > 0.1,
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Transform.rotate(
            angle: float.tilt * (1 - gather) + math.sin(y * 0.7) * 0.05,
            child: CachedMedia(
              identity: item.previewIdentity,
              previewPath: item.previewPath,
              online: widget.online,
              entrance: MediaEntrance.fade,
              placeholder: false,
            ),
          ),
        ),
      ),
    );
  }

  /// Blends colours [amount] of the way towards the paper. Unlike opacity it
  /// keeps pieces opaque, so overlapping ones never show through each other.
  static ColorFilter _wash(double amount) {
    final keep = 1 - amount;
    const paper = FormTokens.paper;
    return ColorFilter.matrix([
      keep, 0, 0, 0, amount * paper.r * 255, //
      0, keep, 0, 0, amount * paper.g * 255, //
      0, 0, keep, 0, amount * paper.b * 255, //
      0, 0, 0, 1, 0,
    ]);
  }
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
