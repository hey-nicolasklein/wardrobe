import 'package:flutter/material.dart';
import 'package:form_mobile/features/wardrobe/wardrobe_filter.dart';

/// Values from apps/web/public/style.css. Keep screen-specific values there aligned.
abstract final class FormTokens {
  static const paper = Color(0xFFF6F5F1);
  static const ink = Color(0xFF242923);
  static const green = Color(0xFF344D3F);
  static const muted = Color(0xFF777B72);
  static const line = Color(0xFFE2E4DC);
  static const chrome = Color(0xFFE9E8DC);
  static const Color surface = Colors.white;
  static const field = Color(0xFFEAECE5);
  static const danger = Color(0xFFA34B3C);
  static const dangerTint = Color(0xFFF6E9E5);
  static const noteInk = Color(0xFF626E5E);
  static const emptyIcon = Color(0xFF9BA694);
  static const uploadTint = Color(0xFFEBEEE6);
  static const uploadLine = Color(0xFFA7B39F);
  static const pill = Color(0xFFEEEDE7);
  static const selectedTint = Color(0xFFDFE8D2);
  static const toggleOff = Color(0xFFB9BEB5);
  static const liked = Color(0xFFFF7788);
  static const toast = Color(0xFF263D30);
  static const checkBadge = Color(0xFFF6F8EF);
  static const checkInk = Color(0xFF49603D);
  static const flatLayPaper = Color(0xFFF0EEE6);
  static const flatLayInk = Color(0xFF26351D);

  static const gutter = 22.0;
  static const gap = 10.0;
  static const inputRadius = 12.0;
  static const cardRadius = 14.0;
  static const panelRadius = 18.0;
  static const sheetRadius = 25.0;
  static const chipRadius = 30.0;
  static const pop = Cubic(0.34, 1.56, 0.64, 1);
  static const easeOut = Cubic(0.22, 1, 0.36, 1);
  static const sheetCurve = Cubic(0.32, 0.72, 0, 1);
  static const quick = Duration(milliseconds: 180);
  static const sheetDuration = Duration(milliseconds: 340);
  static const display = TextStyle(
    fontFamily: 'LibreBaskerville',
    fontSize: 43,
    height: 1.08,
    fontWeight: FontWeight.w400,
    letterSpacing: -1.8,
    color: ink,
  );
  static const heading = TextStyle(
    fontFamily: 'LibreBaskerville',
    fontSize: 29,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.5,
    color: ink,
  );
  static const body = TextStyle(fontSize: 14, height: 1.55, color: ink);
  static const small = TextStyle(fontSize: 12, height: 1.6, color: muted);
  static const eyebrow = TextStyle(
    fontSize: 10,
    letterSpacing: 2,
    fontWeight: FontWeight.w600,
    color: muted,
  );
  static const wordmark = TextStyle(
    fontSize: 18,
    letterSpacing: 5,
    fontWeight: FontWeight.w600,
    color: ink,
  );
  static const TextStyle numerals = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static ({Color ink, Color tint}) category(String category) =>
      switch (category) {
        'tops' ||
        'outerwear' ||
        'dresses' ||
        'top' => (ink: const Color(0xFF6D8A68), tint: const Color(0xFFE5ECE2)),
        'pants' || 'skirt' || 'bottom' => (
          ink: const Color(0xFFAA7D73),
          tint: const Color(0xFFF3E7E3),
        ),
        'shoes' => (
          ink: const Color(0xFF6B8FA2),
          tint: const Color(0xFFE2EDF2),
        ),
        _ => (ink: const Color(0xFFA18A52), tint: const Color(0xFFF2EDDD)),
      };

  static const colorSwatches = <String, Color>{
    'black': Color(0xFF343632),
    'white': Color(0xFFF5F1E7),
    'gray': Color(0xFFB9BDB8),
    'beige': Color(0xFFDED0B8),
    'brown': Color(0xFF99785E),
    'blue': Color(0xFF739BBD),
    'green': Color(0xFF92AD87),
    'yellow': Color(0xFFE6D68E),
    'orange': Color(0xFFDFA67F),
    'red': Color(0xFFC27870),
    'purple': Color(0xFFB9A7C9),
    'pink': Color(0xFFDDA9B8),
    'other': Color(0xFFB8BBA9),
  };

  static Color colorForName(String name) =>
      colorSwatches[colorFamilies(name).firstOrNull] ?? colorSwatches['other']!;

  static const Map<String, ({Color ink, Color tint})> occasions = {
    '': (ink: Color(0xFF75602F), tint: Color(0xFFEEE5CE)),
    'night-out': (ink: Color(0xFF6C5884), tint: Color(0xFFE5E1F0)),
    'party': (ink: Color(0xFF92594F), tint: Color(0xFFF3DFDC)),
    'casual': (ink: Color(0xFF526D54), tint: Color(0xFFDFE9DF)),
  };
}
