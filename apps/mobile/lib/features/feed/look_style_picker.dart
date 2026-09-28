import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/composer_cubit.dart';

/// Photo style picker: one tile per [lookStyles] entry, built like a small
/// print with a sketch of the style's composition above its caption. The
/// selected print lifts and tilts, and every tap fires a shutter flash and
/// makes the sketched person hop.
class LookStylePicker extends StatelessWidget {
  const LookStylePicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The chosen style, or null for automatic.
  final String? selected;
  final ValueChanged<String?> onSelected;

  static const _auto = 'auto';

  @override
  // The side inset leaves room for the tilted, shadowed print: the composer
  // sheet's scroll view clips at the content edge.
  Widget build(BuildContext context) {
    final styles = [_auto, ...lookStyles];
    // Two prints per row, so each gets enough room for its sketch and hint.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          for (var row = 0; row < styles.length; row += 2) ...[
            if (row > 0) const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (column, style)
                    in styles.skip(row).take(2).indexed) ...[
                  if (column > 0) const SizedBox(width: 14),
                  Expanded(
                    child: _StyleTile(
                      style: style,
                      // Checkerboard tilt so neighbouring prints don't look
                      // stamped.
                      tilt: (row ~/ 2 + column).isEven ? -0.035 : 0.035,
                      selected: style == (selected ?? _auto),
                      onTap: () => onSelected(style == _auto ? null : style),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StyleTile extends StatefulWidget {
  const _StyleTile({
    required this.style,
    required this.tilt,
    required this.selected,
    required this.onTap,
  });

  final String style;
  final double tilt;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_StyleTile> createState() => _StyleTileState();
}

class _StyleTileState extends State<_StyleTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shot = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  bool _pressed = false;

  @override
  void dispose() {
    _shot.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.selected) unawaited(HapticFeedback.selectionClick());
    if (!MediaQuery.disableAnimationsOf(context)) {
      unawaited(_shot.forward(from: 0));
    }
    widget.onTap();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FormTokens.lookStyles[widget.style]!;
    final label = context.tr('lookStyle.${widget.style}');
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: _handleTap,
        child: AnimatedSlide(
          offset: Offset(0, widget.selected ? -0.05 : 0),
          duration: motion,
          curve: FormTokens.pop,
          child: AnimatedRotation(
            turns: widget.selected ? widget.tilt / (2 * math.pi) : 0,
            duration: motion,
            curve: FormTokens.pop,
            child: AnimatedScale(
              scale: _pressed ? 0.94 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                decoration: BoxDecoration(
                  color: widget.selected ? Colors.white : colors.tint,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: colors.ink.withValues(
                        alpha: widget.selected ? 0.26 : 0,
                      ),
                      blurRadius: 10,
                      spreadRadius: -3,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: AnimatedBuilder(
                          animation: _shot,
                          builder: (context, _) {
                            final t = _shot.value;
                            final flash = _shot.isAnimating
                                ? 0.85 * (1 - Curves.easeOut.transform(t))
                                : 0.0;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                if (widget.style == LookStylePicker._auto)
                                  // Automatic has no single composition, so
                                  // it shows a spark that pops on tap.
                                  ColoredBox(
                                    color: Color.alphaBlend(
                                      Colors.white.withValues(alpha: 0.5),
                                      colors.tint,
                                    ),
                                    child: Transform.scale(
                                      scale: 1 + math.sin(t * math.pi) * 0.25,
                                      child: Icon(
                                        Icons.auto_awesome,
                                        color: colors.ink,
                                        size: 44,
                                      ),
                                    ),
                                  )
                                else
                                  CustomPaint(
                                    painter: _StyleSketch(
                                      widget.style,
                                      colors,
                                      hop: math.sin(t * math.pi),
                                    ),
                                  ),
                                ColoredBox(
                                  color: Colors.white.withValues(alpha: flash),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: colors.ink,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Two lines reserved, so tiles in a row stay the same
                    // height whether the hint wraps or not.
                    SizedBox(
                      height: 12 * 1.3 * 2,
                      child: Text(
                        context.tr('lookStyleHint.${widget.style}'),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: colors.ink.withValues(alpha: 0.75),
                        ),
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
  }
}

/// Draws a tiny scene that shows where the camera stands for [style]. [hop]
/// (0 → 1 → 0) lifts the person during the tap animation.
class _StyleSketch extends CustomPainter {
  const _StyleSketch(this.style, this.colors, {this.hop = 0});

  final String style;
  final ({Color ink, Color tint}) colors;
  final double hop;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Color.alphaBlend(
          Colors.white.withValues(alpha: 0.5),
          colors.tint,
        ),
    );
    final soft = Paint()..color = colors.ink.withValues(alpha: 0.14);
    final figure = Paint()..color = colors.ink;
    final lift = Offset(0, -hop * h * 0.07);
    switch (style) {
      case 'street':
        // Telephoto bokeh behind a small full-length figure mid-stride.
        for (final (x, y, r) in [
          (0.18, 0.22, 0.13),
          (0.8, 0.16, 0.1),
          (0.86, 0.46, 0.07),
          (0.12, 0.52, 0.06),
        ]) {
          canvas.drawCircle(Offset(w * x, h * y), w * r, soft);
        }
        canvas.drawRect(Rect.fromLTWH(0, h * 0.86, w, h * 0.14), soft);
        _person(canvas, figure, Offset(w * 0.5, h * 0.18) + lift, h * 0.7, 0.5);
      case 'mirror':
        // A standing mirror with the reflection holding up a phone.
        final mirror = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.24, h * 0.07, w * 0.52, h * 0.88),
          Radius.circular(w * 0.26),
        );
        canvas.drawRRect(
          mirror,
          Paint()..color = Colors.white.withValues(alpha: 0.6),
        );
        canvas.drawRRect(
          mirror,
          Paint()
            ..color = colors.ink.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.03,
        );
        final top = Offset(w * 0.5, h * 0.18) + lift;
        _person(canvas, figure, top, h * 0.7, 0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: top + Offset(w * 0.1, h * 0.06),
              width: w * 0.09,
              height: w * 0.15,
            ),
            Radius.circular(w * 0.02),
          ),
          Paint()..color = colors.tint,
        );
      default:
        // Candid: an off-centre figure caught mid-moment on a horizon.
        canvas.drawCircle(Offset(w * 0.24, h * 0.22), w * 0.1, soft);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.8, w, h * 0.2), soft);
        _person(
          canvas,
          figure,
          Offset(w * 0.62, h * 0.2) + lift,
          h * 0.66,
          0.25,
        );
    }
  }

  /// A simple person of [height] whose head top sits at [top]. [stride] spreads
  /// the legs, from 0 (standing) to 1 (full step).
  void _person(
    Canvas canvas,
    Paint paint,
    Offset top,
    double height,
    double stride,
  ) {
    final head = height * 0.1;
    canvas.drawCircle(top + Offset(0, head), head, paint);
    final shoulders = top.dy + head * 2.3;
    final torsoWidth = height * 0.26;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(
          top.dx - torsoWidth / 2,
          shoulders,
          torsoWidth,
          height * 0.4,
        ),
        topLeft: Radius.circular(torsoWidth * 0.4),
        topRight: Radius.circular(torsoWidth * 0.4),
        bottomLeft: Radius.circular(torsoWidth * 0.12),
        bottomRight: Radius.circular(torsoWidth * 0.12),
      ),
      paint,
    );
    final hip = shoulders + height * 0.38;
    final leg = Paint()
      ..color = paint.color
      ..strokeWidth = torsoWidth * 0.36
      ..strokeCap = StrokeCap.round;
    final spread = height * 0.14 * stride;
    for (final side in [-1, 1]) {
      canvas.drawLine(
        Offset(top.dx + side * torsoWidth * 0.24, hip),
        Offset(top.dx + side * (torsoWidth * 0.24 + spread), top.dy + height),
        leg,
      );
    }
  }

  @override
  bool shouldRepaint(_StyleSketch old) =>
      old.style != style || old.colors != colors || old.hop != hop;
}
