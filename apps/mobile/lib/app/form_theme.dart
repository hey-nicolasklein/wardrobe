import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

ThemeData formTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF344D3F),
    primary: const Color(0xFF344D3F),
    surface: const Color(0xFFF6F5F1),
    onSurface: const Color(0xFF242923),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Color(0xFFF6F5F1),
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFFF6F5F1),
      indicatorColor: Color(0xFFE2E4DC),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}
