import 'dart:async';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/feed/flat_lay_widget.dart';
import 'package:form_mobile/features/onboarding/onboarding_pieces.dart';
import 'package:form_mobile/features/onboarding/onboarding_steps.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_components.dart';
import 'package:form_mobile/widgets/form_icon.dart';

/// The Schrank as a shelf of floating demo pieces. Switching between owned
/// and wished-for pieces deals the shelf anew.
class OnboardingClosetStep extends StatefulWidget {
  const OnboardingClosetStep({super.key});

  @override
  State<OnboardingClosetStep> createState() => _OnboardingClosetStepState();
}

class _OnboardingClosetStepState extends State<OnboardingClosetStep> {
  String _collection = 'owning';

  @override
  Widget build(BuildContext context) {
    final pieces = onboardingPieces
        .where((piece) => piece.state == _collection)
        .take(16)
        .toList();
    return OnboardingStepLayout(
      eyebrow: context.tr(LocaleKeys.onboarding_closetEyebrow),
      title: context.tr(LocaleKeys.onboarding_closetTitle),
      body: context.tr(LocaleKeys.onboarding_closetBody),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const columns = 4;
                final cell =
                    (constraints.maxWidth - FormTokens.gap * (columns - 1)) /
                    columns;
                return SingleChildScrollView(
                  child: Wrap(
                    key: ValueKey(_collection),
                    spacing: FormTokens.gap,
                    runSpacing: FormTokens.gap,
                    children: [
                      for (final (index, piece) in pieces.indexed)
                        SizedBox.square(
                          dimension: cell,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: FormTokens.surface,
                              border: Border.all(color: FormTokens.line),
                              borderRadius: BorderRadius.circular(
                                FormTokens.cardRadius,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(9),
                              child: FloatingPiece(
                                piece: piece,
                                angle:
                                    (index.isEven ? -1.0 : 1.0) *
                                    (2 + index % 3),
                                delay: Duration(milliseconds: 45 * index),
                                phase: index * 0.9,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(LocaleKeys.onboarding_closetToggle),
            style: FormTokens.small,
          ),
          FormCollectionToggle(
            selected: _collection,
            labels: {
              'owning': context.tr(LocaleKeys.collection_owning),
              'wanting': context.tr(LocaleKeys.collection_wanting),
            },
            onSelected: (value) {
              unawaited(HapticFeedback.selectionClick());
              setState(() => _collection = value);
            },
          ),
        ],
      ),
    );
  }
}

enum _PieceMode { inspire, tryOn }

/// Pick a piece from the Schrank and either let FORM build a look around it
/// or try it on a figure, like the two actions on a piece's page.
class OnboardingPieceLookStep extends StatefulWidget {
  const OnboardingPieceLookStep({super.key});

  @override
  State<OnboardingPieceLookStep> createState() =>
      _OnboardingPieceLookStepState();
}

class _OnboardingPieceLookStepState extends State<OnboardingPieceLookStep> {
  static final List<OnboardingPiece> _tray = onboardingPieces
      .where((piece) => piece.state == 'owning')
      .toList();
  OnboardingPiece _piece = onboardingPiece('leather-jacket');
  _PieceMode? _mode;
  int _seed = 0;

  void _pick(OnboardingPiece piece) {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _piece = piece;
      _mode = null;
    });
  }

  void _run(_PieceMode mode) => setState(() {
    _mode = mode;
    _seed++;
  });

  @override
  Widget build(BuildContext context) => OnboardingStepLayout(
    eyebrow: context.tr(LocaleKeys.onboarding_pieceEyebrow),
    title: context.tr(LocaleKeys.onboarding_pieceTitle),
    body: context.tr(LocaleKeys.onboarding_pieceBody),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FormTokens.panelRadius),
            child: AnimatedSwitcher(
              duration: FormTokens.sheetDuration,
              switchInCurve: FormTokens.easeOut,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey('$_mode$_seed${_piece.id}'),
                child: switch (_mode) {
                  null => ColoredBox(
                    color: FormTokens.lookStage,
                    child: Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.5,
                        heightFactor: 0.6,
                        child: FloatingPiece(
                          piece: _piece,
                          angle: -6,
                          delay: Duration.zero,
                          phase: 0,
                        ),
                      ),
                    ),
                  ),
                  _PieceMode.inspire => _InspiredLook(
                    piece: _piece,
                    seed: _seed,
                  ),
                  _PieceMode.tryOn => _TryOn(piece: _piece),
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _tray.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final piece = _tray[index];
              final selected = piece.id == _piece.id;
              return Semantics(
                button: true,
                selected: selected,
                label: context.tr('categories.${piece.category}'),
                child: PressableGarment(
                  onTap: () => _pick(piece),
                  child: AnimatedContainer(
                    duration: FormTokens.quick,
                    width: 58,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: selected
                          ? FormTokens.selectedTint
                          : FormTokens.surface,
                      border: Border.all(
                        color: selected ? FormTokens.green : FormTokens.line,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(
                        FormTokens.cardRadius,
                      ),
                    ),
                    child: OnboardingPieceImage(piece: piece),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          spacing: FormTokens.gap,
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _run(_PieceMode.inspire),
                icon: const FormIcon(
                  FormIconName.feed,
                  size: 18,
                  color: FormTokens.surface,
                ),
                label: Text(context.tr(LocaleKeys.inspireItem)),
              ),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _run(_PieceMode.tryOn),
                icon: const FormIcon(FormIconName.person, size: 18),
                label: Text(context.tr(LocaleKeys.lookTryOn)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    ),
  );
}

/// A flat lay built around [piece], which stays highlighted while the rest
/// of the outfit rises in.
class _InspiredLook extends StatelessWidget {
  const _InspiredLook({required this.piece, required this.seed});
  final OnboardingPiece piece;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final look = surpriseOnboardingLook(seed, around: piece);
    return ColoredBox(
      color: FormTokens.flatLayPaper,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: FlatLayBoard(
            garments: [for (final entry in look) entry.garment],
            online: false,
            arrive: true,
            selectedId: piece.id,
            imageBuilder: (item) =>
                OnboardingPieceImage(piece: onboardingPiece(item.id)),
          ),
        ),
      ),
    );
  }
}

/// A figure on a photo backdrop: a light sweeps down and [piece] drops onto
/// the spot where it is worn.
class _TryOn extends StatefulWidget {
  const _TryOn({required this.piece});
  final OnboardingPiece piece;

  // Centre y and size as fractions of the stage height, per category.
  static const _spots = {
    'accessory': (.13, .14),
    'top': (.38, .36),
    'jacket': (.39, .42),
    'pants': (.68, .40),
    'shoes': (.92, .15),
  };

  @override
  State<_TryOn> createState() => _TryOnState();
}

class _TryOnState extends State<_TryOn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        unawaited(
          _controller.forward().then((_) => HapticFeedback.mediumImpact()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (y, size) = _TryOn._spots[widget.piece.category]!;
    return ColoredBox(
      color: FormTokens.lookStage,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final width = constraints.maxWidth;
          final side = size * height;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final sweep = Curves.easeInOut.transform(
                (t / 0.55).clamp(0.0, 1.0),
              );
              final drop = FormTokens.pop.transform(
                ((t - 0.35) / 0.65).clamp(0.0, 1.0),
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _FigurePainter()),
                  ),
                  Positioned(
                    left: width / 2 - side / 2,
                    top: y * height - side / 2 - (1 - drop) * height * 0.5,
                    width: side,
                    height: side,
                    child: Opacity(
                      opacity: drop.clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: (1 - drop) * 0.4,
                        child: OnboardingPieceImage(piece: widget.piece),
                      ),
                    ),
                  ),
                  if (sweep < 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: -height * 0.3 + height * 1.3 * sweep,
                      height: height * 0.3,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00FFFFFF), Color(0x99FFFFFF)],
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Opacity(
                      opacity: drop.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: FormTokens.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            context.tr(LocaleKeys.tryOnBadge).toUpperCase(),
                            style: FormTokens.eyebrow,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// A soft standing figure that stands in for the person's own photo.
class _FigurePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final cx = size.width / 2;
    final paint = Paint()..color = FormTokens.emptyIcon.withValues(alpha: 0.32);
    RRect bar(double left, double top, double width, double height) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, width, height),
          Radius.circular(min(width, height) / 2),
        );

    canvas
      ..drawCircle(Offset(cx, h * 0.12), h * 0.065, paint)
      // Torso and arms.
      ..drawRRect(bar(cx - h * 0.1, h * 0.21, h * 0.2, h * 0.34), paint)
      ..drawRRect(bar(cx - h * 0.155, h * 0.22, h * 0.05, h * 0.3), paint)
      ..drawRRect(bar(cx + h * 0.105, h * 0.22, h * 0.05, h * 0.3), paint)
      // Legs.
      ..drawRRect(bar(cx - h * 0.09, h * 0.5, h * 0.08, h * 0.42), paint)
      ..drawRRect(bar(cx + h * 0.01, h * 0.5, h * 0.08, h * 0.42), paint);
  }

  @override
  bool shouldRepaint(_FigurePainter oldDelegate) => false;
}
