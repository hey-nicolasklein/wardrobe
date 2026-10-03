import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
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
class PhotoFan extends StatelessWidget {
  const PhotoFan({
    required this.looks,
    required this.online,
    required this.photoSize,
    required this.spread,
    this.angle = 0.11,
    this.offset = 0.36,
    super.key,
  });

  final List<CachedLook> looks;
  final bool online;
  final Size photoSize;
  final double spread;

  /// Rotation of the outer photos in radians, at a spread of 1.
  final double angle;

  /// Sideways shift of the outer photos as a share of the photo width.
  final double offset;

  @override
  Widget build(BuildContext context) {
    final photos = looks.where((r) => r.look.assetId != null).take(3).toList();
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
  });

  final CachedLook? record;
  final bool online;
  final Size size;
  final bool elevated;

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
          child: assetId == null
              ? const SizedBox.expand()
              : CachedMedia(
                  identity: assetId,
                  previewPath: record!.previewPath(assetId),
                  online: online,
                  fit: BoxFit.cover,
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
                color: FormTokens.surface,
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
