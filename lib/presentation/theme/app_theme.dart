import 'package:curel/presentation/theme/app_tokens.dart';
import 'package:flutter/material.dart';

ThemeData buildThemeData([AppThemeTokens? tokens]) {
  final t = tokens ?? $tokens;

  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: t.background,
    colorScheme: ColorScheme.dark(
      primary: t.accent,
      surface: t.surface,
      error: t.error,
    ),
    textTheme: const TextTheme(
      bodySmall: TextStyle(fontFamily: 'monospace'),
      bodyMedium: TextStyle(fontFamily: 'monospace'),
      bodyLarge: TextStyle(fontFamily: 'monospace'),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    cardTheme: const CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.zero),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero),
    ),
    snackBarTheme: const SnackBarThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    chipTheme: const ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
  );
}
