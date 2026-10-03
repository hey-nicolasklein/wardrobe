import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:form_mobile/generated/locale_keys.g.dart';
import 'package:form_mobile/widgets/form_icon.dart';

/// The four occasions a look can be made for, as composer and Looks show
/// them. A null value is the surprise occasion.
const List<({FormIconName icon, String label, String? value})> occasionPresets =
    [
      (
        value: null,
        icon: FormIconName.shuffle,
        label: LocaleKeys.composerOccasionSurprise,
      ),
      (
        value: 'night-out',
        icon: FormIconName.moon,
        label: LocaleKeys.composerOccasionNightOut,
      ),
      (
        value: 'party',
        icon: FormIconName.party,
        label: LocaleKeys.composerOccasionParty,
      ),
      (
        value: 'casual',
        icon: FormIconName.top,
        label: LocaleKeys.composerOccasionCasual,
      ),
    ];

/// An occasion preset that shrinks while pressed and plays an icon-specific
/// animation on every tap.
class OccasionTile extends StatefulWidget {
  const OccasionTile({
    required this.icon,
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
    this.caption,
    this.compact = false,
    super.key,
  });

  final FormIconName icon;
  final String label;
  final ({Color tint, Color ink}) colors;
  final bool selected;
  final VoidCallback onTap;

  /// A second line under the label, e.g. how many looks it holds.
  final String? caption;

  /// A single-line chip with the icon beside the label, for tight rows like
  /// the composer.
  final bool compact;

  @override
  State<OccasionTile> createState() => OccasionTileState();
}

class OccasionTileState extends State<OccasionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool _pressed = false;

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  void _handleTap() {
    unawaited(_tap.forward(from: 0));
    widget.onTap();
  }

  /// Transforms the icon for tap progress [t] (0 → 1), one motion per preset:
  /// shuffle spins, moon swings, party pops and shakes, top hops.
  Widget _animateIcon(double t, Widget icon) {
    final fade = 1 - t;
    return switch (widget.icon) {
      FormIconName.shuffle => Transform.rotate(
        angle: Curves.easeInOutBack.transform(t) * 2 * math.pi,
        child: icon,
      ),
      FormIconName.moon => Transform.rotate(
        angle: math.sin(t * 3 * math.pi) * fade * 0.6,
        child: icon,
      ),
      FormIconName.party => Transform.rotate(
        angle: math.sin(t * 5 * math.pi) * fade * 0.35,
        child: Transform.scale(
          scale: 1 + math.sin(t * math.pi) * 0.3,
          child: icon,
        ),
      ),
      _ => Transform.translate(
        offset: Offset(0, -math.sin(t * math.pi) * 10),
        child: icon,
      ),
    };
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: widget.compact
                ? const EdgeInsets.fromLTRB(12, 10, 16, 10)
                : const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
            decoration: BoxDecoration(
              color: colors.tint,
              borderRadius: BorderRadius.circular(widget.compact ? 30 : 15),
              border: Border.all(
                color: widget.selected ? colors.ink : Colors.transparent,
                width: 2,
              ),
            ),
            child: widget.compact ? _compactContent() : _tileContent(),
          ),
        ),
      ),
    );
  }

  Widget _icon() => AnimatedScale(
    scale: widget.selected ? 1.15 : 1,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutBack,
    child: AnimatedBuilder(
      animation: _tap,
      builder: (context, icon) => _animateIcon(_tap.value, icon!),
      child: FormIcon(
        widget.icon,
        color: widget.colors.ink,
        size: widget.compact ? 18 : 23,
      ),
    ),
  );

  Widget _compactContent() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _icon(),
      const SizedBox(width: 8),
      Text(
        widget.label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: widget.colors.ink,
        ),
      ),
    ],
  );

  Widget _tileContent() => Column(
    children: [
      _icon(),
      const SizedBox(height: 12),
      // Long German labels shrink a little instead of cutting off.
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          widget.label,
          maxLines: 1,
          style: TextStyle(fontSize: 11, color: widget.colors.ink),
        ),
      ),
      if (widget.caption case final caption?)
        Text(
          caption,
          maxLines: 1,
          style: TextStyle(
            fontSize: 11,
            color: widget.colors.ink.withValues(alpha: 0.65),
          ),
        ),
    ],
  );
}
