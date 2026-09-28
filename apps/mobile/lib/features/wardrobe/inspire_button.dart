import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';

/// The item page's hero action. A light sheen sweeps across it, the sparkle
/// twinkles, and it squishes on press, so it reads as the fun thing to tap.
/// Motion stops while disabled or when the OS asks for reduced motion.
class InspireButton extends StatefulWidget {
  const InspireButton({
    required this.title,
    required this.subtitle,
    required this.onPressed,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  @override
  State<InspireButton> createState() => _InspireButtonState();
}

class _InspireButtonState extends State<InspireButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  bool _pressed = false;

  static const _gradientStart = Color(0xFF2E4A3A);
  static const _gradientEnd = Color(0xFF5E7F5A);
  static const _spark = Color(0xFFF3D98B);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  @override
  void didUpdateWidget(InspireButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLoop();
  }

  void _syncLoop() {
    final animate =
        widget.onPressed != null && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_loop.isAnimating) {
      unawaited(_loop.repeat());
    } else if (!animate) {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.title,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: () => _setPressed(false),
        onTap: enabled
            ? () {
                unawaited(HapticFeedback.mediumImpact());
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 160),
          curve: _pressed ? Curves.easeOut : FormTokens.pop,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: FormTokens.quick,
            child: AnimatedBuilder(
              animation: _loop,
              builder: (context, _) => _body(_loop.value),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(double t) {
    // The sheen crosses during the first 40% of each loop, then rests.
    final sweep = Curves.easeInOut.transform((t / 0.4).clamp(0.0, 1.0));
    final twinkle = math.sin(t * 2 * math.pi);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FormTokens.panelRadius),
        gradient: const LinearGradient(
          colors: [_gradientStart, _gradientEnd],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _gradientStart.withValues(alpha: 0.28 + twinkle * 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FormTokens.panelRadius),
        child: Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment(-3 + sweep * 6, 0),
                widthFactor: 0.35,
                child: Transform(
                  transform: Matrix4.skewX(-0.35),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.22),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                    child: Transform.rotate(
                      angle: twinkle * 0.25,
                      child: Transform.scale(
                        scale: 1 + twinkle.abs() * 0.18,
                        child: const Icon(
                          Icons.auto_awesome,
                          color: _spark,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(twinkle.clamp(0.0, 1.0) * 4, 0),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
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
