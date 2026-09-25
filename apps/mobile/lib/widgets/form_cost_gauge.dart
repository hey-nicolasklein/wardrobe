import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:form_mobile/app/form_tokens.dart';

const costGaugeRadius = 82.0;
const costGaugeWidth = 15.0;
const double costGaugeLength = math.pi * costGaugeRadius;
const Color costLooksColor = FormTokens.green;
const Color costWardrobeColor = FormTokens.costWardrobe;
const Color costDetectionColor = FormTokens.costDetection;

class CostGaugeArc {
  const CostGaugeArc(this.index, this.start, this.length);

  final int index;
  final double start;
  final double length;
}

/// The PWA reserves a round cap's width for tiny shares and takes that space
/// proportionally from larger shares. Zero shares claim neither space nor gaps.
List<CostGaugeArc> costGaugeArcs(List<int> values) {
  final positive = values.map((value) => math.max(value, 0)).toList();
  final total = positive.fold(0, (sum, value) => sum + value);
  if (total == 0) return const [];
  final count = positive.where((value) => value > 0).length;
  final gap = count > 1 ? 4.0 : 0.0;
  final available = costGaugeLength - gap * (count - 1);
  final spans = positive.map((value) => value / total * available).toList();
  final deficit = spans.fold<double>(
    0,
    (sum, span) => sum + (span > 0 ? math.max(costGaugeWidth - span, 0) : 0),
  );
  final surplus = spans.fold<double>(
    0,
    (sum, span) => sum + math.max(span - costGaugeWidth, 0),
  );
  var cursor = 0.0;
  final arcs = <CostGaugeArc>[];
  for (var index = 0; index < spans.length; index++) {
    var span = spans[index];
    if (span <= 0) continue;
    if (deficit > 0 && surplus > 0) {
      span = span < costGaugeWidth
          ? costGaugeWidth
          : span - (span - costGaugeWidth) * deficit / surplus;
    }
    arcs.add(CostGaugeArc(index, cursor, span));
    cursor += span + gap;
  }
  return List.unmodifiable(arcs);
}

/// PWA half ring with localized text supplied by callers.
class FormCostGauge extends StatelessWidget {
  const FormCostGauge({
    required this.values,
    required this.total,
    required this.label,
    super.key,
  }) : assert(values.length == 3, 'The cost gauge has three sources');

  final List<int> values;
  final String total;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: AspectRatio(
        aspectRatio: 200 / 106,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 900),
          builder: (context, progress, child) => CustomPaint(
            painter: _CostGaugePainter(costGaugeArcs(values), progress),
            child: Stack(
              children: [
                Positioned(
                  left: 40,
                  right: 40,
                  bottom: 0,
                  child: Opacity(
                    opacity: FormTokens.easeOut.transform(
                      ((progress * 900 - 120) / 460).clamp(0.0, 1.0),
                    ),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  total,
                  style: FormTokens.heading
                      .copyWith(fontSize: 34, letterSpacing: -1.2, height: 1)
                      .merge(FormTokens.numerals),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: FormTokens.eyebrow.copyWith(
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CostGaugePainter extends CustomPainter {
  _CostGaugePainter(this.arcs, this.progress);

  final List<CostGaugeArc> arcs;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 200, size.height / 106);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = costGaugeWidth;
    final bounds = Rect.fromCircle(
      center: const Offset(100, 98),
      radius: costGaugeRadius,
    );
    void draw(double start, double length, Color color) {
      paint.color = color;
      canvas.drawArc(
        bounds,
        math.pi + (start + costGaugeWidth / 2) / costGaugeRadius,
        math.max(length - costGaugeWidth, 0.01) / costGaugeRadius,
        false,
        paint,
      );
    }

    draw(0, costGaugeLength, FormTokens.costTrack);
    const colors = [costLooksColor, costWardrobeColor, costDetectionColor];
    for (var order = 0; order < arcs.length; order++) {
      final arc = arcs[order];
      final reveal = FormTokens.easeOut.transform(
        ((progress * 900 - order * 140) / 620).clamp(0.0, 1.0),
      );
      if (reveal == 0) continue;
      draw(
        arc.start,
        costGaugeWidth + (arc.length - costGaugeWidth) * reveal,
        colors[arc.index].withValues(alpha: reveal),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CostGaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.arcs != arcs;
}
