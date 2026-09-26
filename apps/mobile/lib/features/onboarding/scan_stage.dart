import 'dart:async';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/onboarding/onboarding_pieces.dart';
import 'package:form_mobile/features/onboarding/onboarding_steps.dart';

/// Demo pieces lying on a photo while FORM analyses it: a band sweeps over
/// the photo until [scanEnd] of [progress], then each piece is framed with
/// its category, one after another.
class ScanStage extends StatelessWidget {
  const ScanStage({required this.pieces, required this.progress, super.key});

  /// Three demo photos, as piece ids.
  static const photos = [
    ['jersey', 'balloon-pants', 'maroon-sneaker'],
    ['teddy-coat', 'turtleneck', 'brown-trousers'],
    ['croc-jacket', 'black-pants', 'sunglasses'],
  ];
  static const scanEnd = 0.42;

  // Centre x and y as stage fractions, size as a fraction of stage height,
  // angle in degrees.
  static const _layout = [
    (.25, .47, .80, -7.0),
    (.56, .52, .82, 3.0),
    (.83, .62, .54, 9.0),
  ];

  final List<OnboardingPiece> pieces;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(FormTokens.panelRadius),
    child: ColoredBox(
      color: FormTokens.lookStage,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final band = height * 0.3;
          Rect frame(int index, [double shrink = 1]) {
            final (x, y, size, _) = _layout[index];
            final side = min(size * height, width * 0.46) * shrink;
            return Rect.fromCenter(
              center: Offset(x * width, y * height),
              width: side,
              height: side,
            );
          }

          return Stack(
            children: [
              for (final (index, piece) in pieces.indexed)
                Positioned.fromRect(
                  rect: frame(index),
                  child: Transform.rotate(
                    angle: _layout[index].$4 * pi / 180,
                    child: OnboardingPieceImage(piece: piece),
                  ),
                ),
              AnimatedBuilder(
                animation: progress,
                builder: (context, _) {
                  final t = (progress.value / scanEnd).clamp(0.0, 1.0);
                  return Positioned(
                    left: 0,
                    right: 0,
                    top: -band + (height + band) * t,
                    height: band,
                    child: Opacity(
                      opacity: t >= 1 || progress.value == 0 ? 0 : 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              FormTokens.green.withValues(alpha: 0),
                              FormTokens.green.withValues(alpha: 0.22),
                            ],
                          ),
                          border: const Border(
                            bottom: BorderSide(
                              color: FormTokens.green,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              for (final (index, piece) in pieces.indexed)
                () {
                  final box = CurvedAnimation(
                    parent: progress,
                    curve: Interval(
                      scanEnd + index * 0.07,
                      min(scanEnd + 0.16 + index * 0.07, 1),
                      curve: FormTokens.pop,
                    ),
                  );
                  return Positioned.fromRect(
                    rect: frame(index, 0.92),
                    child: FadeTransition(
                      opacity: box.drive(Tween(begin: 0, end: 1)),
                      child: ScaleTransition(
                        scale: box.drive(Tween(begin: 1.3, end: 1)),
                        child: _DetectionBox(
                          label: context.tr('categories.${piece.category}'),
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          );
        },
      ),
    ),
  );
}

/// [ScanStage] on repeat, moving to the next demo photo every round. Each
/// round fades the photo in, scans, holds the result and fades out.
class LoopingScanStage extends StatefulWidget {
  const LoopingScanStage({super.key});

  @override
  State<LoopingScanStage> createState() => _LoopingScanStageState();
}

class _LoopingScanStageState extends State<LoopingScanStage>
    with SingleTickerProviderStateMixin {
  static const _fadeIn = 0.06;
  static const _fadeOut = 0.92;

  late final AnimationController _round;
  late final Animation<double> _progress;
  int _photo = 0;

  @override
  void initState() {
    super.initState();
    _round =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 4600),
        )..addStatusListener((status) {
          if (status != AnimationStatus.completed || !mounted) return;
          setState(() => _photo = (_photo + 1) % ScanStage.photos.length);
          unawaited(_round.forward(from: 0));
        });
    _progress = CurvedAnimation(
      parent: _round,
      curve: const Interval(_fadeIn, 0.78),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _round
        ..stop()
        // Rests on the finished scan with every piece framed.
        ..value = 0.8;
    } else if (!_round.isAnimating) {
      unawaited(_round.forward());
    }
  }

  @override
  void dispose() {
    _round.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _round,
    builder: (context, child) {
      final v = _round.value;
      final opacity = v < _fadeIn
          ? v / _fadeIn
          : v > _fadeOut
          ? (1 - v) / (1 - _fadeOut)
          : 1.0;
      return Opacity(opacity: opacity.clamp(0, 1), child: child);
    },
    child: ScanStage(
      key: ValueKey(_photo),
      pieces: [
        for (final id in ScanStage.photos[_photo]) onboardingPiece(id),
      ],
      progress: _progress,
    ),
  );
}

class _DetectionBox extends StatelessWidget {
  const _DetectionBox({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white, width: 2),
      borderRadius: BorderRadius.circular(FormTokens.inputRadius),
    ),
    child: Align(
      alignment: Alignment.topLeft,
      child: Container(
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(FormTokens.chipRadius),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FormTokens.small.copyWith(
            fontSize: 10,
            height: 1.3,
            color: FormTokens.green,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
