import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:form_mobile/app/form_tokens.dart';

ThemeData formTheme() {
  const scheme = ColorScheme.light(
    primary: FormTokens.green,
    primaryContainer: FormTokens.field,
    onPrimaryContainer: FormTokens.green,
    secondary: FormTokens.green,
    onSecondary: Colors.white,
    secondaryContainer: FormTokens.field,
    onSecondaryContainer: FormTokens.green,
    tertiary: FormTokens.muted,
    onTertiary: Colors.white,
    tertiaryContainer: FormTokens.chrome,
    onTertiaryContainer: FormTokens.ink,
    surface: FormTokens.paper,
    onSurface: FormTokens.ink,
    onSurfaceVariant: FormTokens.muted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: FormTokens.paper,
    surfaceContainer: FormTokens.field,
    surfaceContainerHigh: FormTokens.chrome,
    surfaceContainerHighest: FormTokens.line,
    error: FormTokens.danger,
    errorContainer: FormTokens.dangerTint,
    onErrorContainer: FormTokens.danger,
    outline: FormTokens.line,
    outlineVariant: FormTokens.line,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(colorScheme: scheme);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(FormTokens.cardRadius),
  );
  final button = ButtonStyle(
    elevation: const WidgetStatePropertyAll(0),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    shape: WidgetStatePropertyAll(shape),
    minimumSize: const WidgetStatePropertyAll(Size(44, 50)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(vertical: 15, horizontal: 20),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    ),
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(FormTokens.inputRadius),
    borderSide: const BorderSide(color: FormTokens.line),
  );
  return base.copyWith(
    scaffoldBackgroundColor: FormTokens.paper,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    textTheme: base.textTheme.copyWith(
      displayLarge: FormTokens.display,
      displayMedium: FormTokens.display,
      headlineLarge: FormTokens.display,
      headlineMedium: FormTokens.heading,
      headlineSmall: FormTokens.heading,
      titleLarge: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: FormTokens.ink,
      ),
      bodyLarge: FormTokens.body.copyWith(fontSize: 16),
      bodyMedium: FormTokens.body,
      bodySmall: FormTokens.small,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: FormTokens.paper,
      foregroundColor: FormTokens.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: FormTokens.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? FormTokens.green.withValues(alpha: 0.45)
              : FormTokens.green,
        ),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: button.copyWith(
        backgroundColor: const WidgetStatePropertyAll(FormTokens.green),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button.copyWith(
        backgroundColor: const WidgetStatePropertyAll(FormTokens.field),
        side: const WidgetStatePropertyAll(BorderSide.none),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
      ),
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(44, 44)),
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(13),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: FormTokens.green),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: FormTokens.danger),
      ),
      floatingLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: FormTokens.paper,
      selectedColor: FormTokens.green,
      secondarySelectedColor: FormTokens.green,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      side: const BorderSide(color: FormTokens.line),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FormTokens.chipRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      labelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          fontSize: 13,
          color: states.contains(WidgetState.selected)
              ? Colors.white
              : FormTokens.ink,
        ),
      ),
      secondaryLabelStyle: const TextStyle(fontSize: 13, color: Colors.white),
      checkmarkColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FormTokens.panelRadius),
        side: const BorderSide(color: FormTokens.line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: FormTokens.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleSize: Size(38, 5),
      dragHandleColor: Color(0x261D281C),
      modalBarrierColor: Color(0x661D281C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormTokens.sheetRadius),
        ),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: FormTokens.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: shape,
    ),
    dividerTheme: const DividerThemeData(color: FormTokens.line, thickness: 1),
    listTileTheme: const ListTileThemeData(
      iconColor: FormTokens.green,
      contentPadding: EdgeInsets.symmetric(vertical: 4),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: FormTokens.green,
      linearTrackColor: FormTokens.line,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: FormTokens.green,
      foregroundColor: Colors.white,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}
