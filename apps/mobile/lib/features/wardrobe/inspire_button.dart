import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:form_mobile/app/form_tokens.dart';
import 'package:form_mobile/widgets/form_icon.dart';

/// A look action on the item page: an icon, a title and a subtitle that says
/// what the action does. Two sit side by side. The primary card is forest,
/// the secondary one white with a hairline. Like the tabs it sinks on press
/// and springs back, and it stays flat at rest.
class InspireButton extends StatefulWidget {
  const InspireButton({
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.icon = const FormIcon(FormIconName.feed, size: 21),
    this.primary = true,
    super.key,
  });

  /// Drawn in the card's ink colour, see [IconTheme].
  final Widget icon;
  final bool primary;
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
    final ink = widget.primary ? FormTokens.surface : FormTokens.green;
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
                color: widget.primary ? FormTokens.green : FormTokens.surface,
                border: widget.primary
                    ? null
                    : Border.all(color: FormTokens.line),
                borderRadius: BorderRadius.circular(FormTokens.cardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.primary
                            ? FormTokens.surface.withValues(alpha: 0.14)
                            : FormTokens.selectedTint,
                      ),
                      child: IconTheme(
                        data: IconThemeData(color: ink, size: 19),
                        child: widget.icon,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.primary
                            ? FormTokens.surface
                            : FormTokens.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: FormTokens.small.copyWith(
                        color: widget.primary
                            ? FormTokens.surface.withValues(alpha: 0.85)
                            : FormTokens.noteInk,
                        height: 1.4,
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
