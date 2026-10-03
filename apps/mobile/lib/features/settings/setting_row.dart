import 'package:flutter/material.dart';
import 'package:form_mobile/app/form_tokens.dart';

/// One line inside a settings panel: label on the left, muted value hugging
/// the right edge. With [onTap] the row becomes tappable and shows a chevron.
/// [color] tints the label, used for destructive rows.
class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.label,
    this.value,
    this.onTap,
    this.color,
    this.chevron = true,
    super.key,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Color? color;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Text(label, style: FormTokens.body.copyWith(color: color)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value ?? '',
              textAlign: TextAlign.end,
              style: FormTokens.small,
            ),
          ),
          if (onTap != null && chevron)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: FormTokens.muted,
              ),
            ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// Hairline between [SettingRow]s inside one panel.
class SettingDivider extends StatelessWidget {
  const SettingDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: FormTokens.line);
}
