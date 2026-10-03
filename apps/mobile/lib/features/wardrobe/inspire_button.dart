import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/widgets/form_icon.dart';

/// The item page's one look action: a forest row with the looks icon, a title
/// and a subtitle. Like the tabs it sinks on press and springs back, and it
/// stays flat at rest.
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

class _InspireButtonState extends State<InspireButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final duration = animate ? FormTokens.quick : Duration.zero;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${widget.title}, ${widget.subtitle}',
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: () => _setPressed(false),
        onTap: enabled
            ? () {
                unawaited(HapticFeedback.lightImpact());
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed && animate ? 0.97 : 1,
          duration: duration,
          curve: _pressed ? Curves.easeOut : FormTokens.pop,
          child: AnimatedOpacity(
            opacity: enabled ? (_pressed ? 0.85 : 1) : 0.45,
            duration: duration,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: FormTokens.green,
                borderRadius: BorderRadius.circular(FormTokens.cardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: FormTokens.surface.withValues(alpha: 0.12),
                      ),
                      child: const FormIcon(
                        FormIconName.feed,
                        size: 21,
                        color: FormTokens.surface,
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
                              color: FormTokens.surface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            style: FormTokens.small.copyWith(
                              color: FormTokens.surface.withValues(alpha: 0.75),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const RotatedBox(
                      quarterTurns: 2,
                      child: FormIcon(
                        FormIconName.arrow,
                        size: 20,
                        color: FormTokens.surface,
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
