import 'dart:async';

import 'package:flutter/material.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/feed_domain.dart';
import 'package:form_mobile/features/feed/flat_lay_layout.dart';
import 'package:form_mobile/models/wardrobe.dart';
import 'package:form_mobile/repository/wardrobe_repository.dart';
import 'package:form_mobile/widgets/cached_media.dart';

class FlatLayBoard extends StatelessWidget {
  const FlatLayBoard({
    required this.garments,
    required this.online,
    this.onGarmentTap,
    this.selectedId,
    this.entrance,
    this.arrive = false,
    this.imageBuilder,
    super.key,
  });

  final List<LookGarment> garments;
  final bool online;
  final ValueChanged<String>? onGarmentTap;
  final String? selectedId;

  /// Drives the pieces rising into place one after another. Runs 0 → 1 over
  /// [entranceDuration]; without it the board is drawn at rest.
  final Animation<double>? entrance;

  /// For a look that is still being put together: each piece rises in by
  /// itself when it first appears, and pieces glide when later arrivals
  /// shift the layout. Takes precedence over [entrance].
  final bool arrive;

  /// Draws a piece's image. Defaults to its cached shelf image.
  final Widget Function(WardrobeItem item)? imageBuilder;

  static const _highlight = Duration(milliseconds: 320);
  static const _glide = Duration(milliseconds: 520);
  static const _rise = 420;
  static const _stagger = 35;

  static Duration entranceDuration(int count) =>
      Duration(milliseconds: _rise + _stagger * (count - 1).clamp(0, 12));

  Widget _enter(int index, int count, Widget child) {
    final total = entranceDuration(count).inMilliseconds;
    final start = (index.clamp(0, 12) * _stagger) / total;
    return _PieceEntrance(
      entrance: entrance,
      interval: Interval(
        start,
        (start + _rise / total).clamp(0, 1),
        curve: FormTokens.easeOut,
      ),
      arrive: arrive,
      delay: Duration(milliseconds: index.clamp(0, 12) * _stagger),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = garments
        .where((garment) => garment.item != null)
        .map((garment) => garment.item!)
        .toList();
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final layout = flatLayLayout(items);
    return AspectRatio(
      aspectRatio: 100 / 125,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // The highlighted piece is drawn last so it grows over its
              // neighbours.
              for (final (index, placement) in [
                ...layout.indexed.where(
                  (entry) => entry.$2.item.id != selectedId,
                ),
                ...layout.indexed.where(
                  (entry) => entry.$2.item.id == selectedId,
                ),
              ])
                () {
                  final garment = garments.firstWhere(
                    (entry) => entry.id == placement.item.id,
                  );
                  final size = placement.size / 100 * width;
                  final left = placement.x / 100 * width - size / 2;
                  final top = placement.y / 125 * height - size / 2;
                  final child = garment.available
                      ? imageBuilder?.call(garment.item!) ??
                            CachedMedia(
                              identity: garment.item!.previewIdentity,
                              previewPath: garment.item!.previewPath,
                              online: online,
                            )
                      : Center(
                          child: Text(
                            garment.item?.metadata.name ?? garment.id,
                            textAlign: TextAlign.center,
                            style: FormTokens.small,
                          ),
                        );
                  return AnimatedPositioned(
                    key: ValueKey(garment.id),
                    duration: arrive ? _glide : Duration.zero,
                    curve: FormTokens.easeOut,
                    left: left,
                    top: top,
                    width: size,
                    height: size,
                    child: _enter(
                      index,
                      layout.length,
                      AnimatedRotation(
                        turns: placement.angle / 360,
                        duration: arrive ? _glide : Duration.zero,
                        curve: FormTokens.easeOut,
                        child: PressableGarment(
                          onTap: onGarmentTap == null || !garment.available
                              ? null
                              : () => onGarmentTap!(garment.id),
                          // The highlighted piece grows while the others
                          // step back, instead of drawing a frame.
                          child: AnimatedOpacity(
                            duration: _highlight,
                            curve: FormTokens.easeOut,
                            opacity:
                                selectedId == null || selectedId == garment.id
                                ? 1
                                : 0.4,
                            child: AnimatedScale(
                              duration: _highlight,
                              curve: FormTokens.pop,
                              scale: selectedId == garment.id ? 1.15 : 1,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          );
        },
      ),
    );
  }
}

/// Rises a piece into place. Follows the board's shared [entrance], or with
/// [arrive] plays once on its own after [delay] when the piece first mounts.
class _PieceEntrance extends StatefulWidget {
  const _PieceEntrance({
    required this.entrance,
    required this.interval,
    required this.arrive,
    required this.delay,
    required this.child,
  });

  final Animation<double>? entrance;
  final Curve interval;
  final bool arrive;
  final Duration delay;
  final Widget child;

  @override
  State<_PieceEntrance> createState() => _PieceEntranceState();
}

class _PieceEntranceState extends State<_PieceEntrance>
    with SingleTickerProviderStateMixin {
  static const _rise = Duration(milliseconds: 560);

  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: widget.delay + _rise,
  );

  @override
  void initState() {
    super.initState();
    if (widget.arrive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (MediaQuery.disableAnimationsOf(context)) {
          _arrival.value = 1;
        } else {
          unawaited(_arrival.forward());
        }
      });
    } else {
      _arrival.value = 1;
    }
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  Animation<double> get _animation {
    if (widget.arrive || widget.entrance == null) {
      final total = _arrival.duration!.inMilliseconds;
      return CurvedAnimation(
        parent: _arrival,
        curve: Interval(
          widget.delay.inMilliseconds / total,
          1,
          curve: FormTokens.easeOut,
        ),
      );
    }
    return CurvedAnimation(parent: widget.entrance!, curve: widget.interval);
  }

  @override
  Widget build(BuildContext context) {
    final animation = _animation;
    return AnimatedBuilder(
      animation: animation,
      child: widget.child,
      builder: (context, child) {
        final t = animation.value;
        return Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
          ),
        );
      },
    );
  }
}

/// Grows a garment while a finger rests on it. It settles back when the
/// finger lifts or drags off and cancels. Without [onTap] it stays still.
class PressableGarment extends StatefulWidget {
  const PressableGarment({required this.onTap, required this.child, super.key});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<PressableGarment> createState() => _PressableGarmentState();
}

class _PressableGarmentState extends State<PressableGarment> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
    onTapUp: (_) => _setPressed(false),
    onTapCancel: () => _setPressed(false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: _pressed ? 1.12 : 1,
      duration: const Duration(milliseconds: 160),
      curve: _pressed ? Curves.easeOutBack : FormTokens.easeOut,
      child: widget.child,
    ),
  );
}
