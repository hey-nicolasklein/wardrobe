import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/features/onboarding/onboarding_pieces.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';

enum FormEmptyScene { wardrobe, owning, wishlist, looks, archive, costs }

/// A few sample pieces from the onboarding closet, at rest until touched.
class FormEmptyGarments extends StatelessWidget {
  const FormEmptyGarments({required this.scene, super.key});

  final FormEmptyScene scene;

  @override
  Widget build(BuildContext context) {
    final pieces = switch (scene) {
      FormEmptyScene.wardrobe => [
        'leather-jacket',
        'jersey',
        'balloon-pants',
        'maroon-sneaker',
      ],
      FormEmptyScene.owning => ['striped-shirt', 'shorts', 'white-sneaker'],
      FormEmptyScene.wishlist => ['olive-jacket', 'black-sneaker'],
      FormEmptyScene.looks => ['white-tee', 'brown-trousers', 'high-top'],
      FormEmptyScene.archive => ['turtleneck', 'brown-trousers'],
      FormEmptyScene.costs => ['striped-shirt', 'white-sneaker'],
    };
    final quiet = scene == FormEmptyScene.archive;
    return SizedBox(
      width: 280,
      height: 164,
      child: Opacity(
        opacity: quiet ? 0.55 : 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (index, id) in pieces.indexed)
              Positioned(
                left: switch (pieces.length) {
                  2 => 32.0 + index * 104,
                  3 => [20.0, 112.0, 176.0][index],
                  _ => [0.0, 67.0, 132.0, 202.0][index],
                },
                top: [8.0, 0.0, 32.0, 72.0][index],
                child: _TouchablePiece(
                  key: ValueKey('${scene.name}-$id'),
                  piece: onboardingPiece(id),
                  angle: [-0.16, 0.10, -0.08, 0.16][index],
                  size: index == pieces.length - 1 ? 88 : 112,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TouchablePiece extends StatefulWidget {
  const _TouchablePiece({
    required this.piece,
    required this.angle,
    required this.size,
    super.key,
  });

  final OnboardingPiece piece;
  final double angle;
  final double size;

  @override
  State<_TouchablePiece> createState() => _TouchablePieceState();
}

class _TouchablePieceState extends State<_TouchablePiece>
    with SingleTickerProviderStateMixin {
  late final _spring = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 560),
  );
  Offset _offset = Offset.zero;

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _release() {
    unawaited(HapticFeedback.lightImpact());
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _offset = Offset.zero);
      return;
    }
    unawaited(_spring.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.tr('categories.${widget.piece.category}'),
    hint: context.tr(LocaleKeys.emptyPieceHint),
    child: GestureDetector(
      onTap: _release,
      onPanStart: (_) {
        if (_spring.isCompleted) _offset = Offset.zero;
        _spring
          ..stop()
          ..value = 0;
      },
      onPanUpdate: (details) => setState(
        () => _offset = Offset(
          (_offset.dx + details.delta.dx).clamp(-32, 32),
          (_offset.dy + details.delta.dy).clamp(-24, 24),
        ),
      ),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: AnimatedBuilder(
        animation: _spring,
        builder: (context, child) {
          final reduced = MediaQuery.disableAnimationsOf(context);
          final t = reduced ? 1.0 : FormTokens.pop.transform(_spring.value);
          final lift = reduced ? 0.0 : 1 - t;
          return Transform.translate(
            offset: _offset * lift,
            child: Transform.rotate(
              angle: widget.angle + 0.14 * lift,
              child: Transform.scale(scale: 1 - 0.05 * lift, child: child),
            ),
          );
        },
        child: ExcludeSemantics(
          child: Image.asset(
            widget.piece.asset,
            width: widget.size,
            height: 128,
            fit: BoxFit.contain,
          ),
        ),
      ),
    ),
  );
}
