import 'package:flutter/material.dart';

/// Paleta y tipografía base de LAIN: fondo profundo, cian para lo propio.
abstract final class LainColors {
  static const background = Color(0xFF0B0F1A);
  static const surface = Color(0xFF151B2B);
  static const surfaceHigh = Color(0xFF1E2638);
  static const primary = Color(0xFF5AC8FA);
  static const onPrimary = Color(0xFF04121C);
  static const userBubble = Color(0xFF1F6FEB);
  static const lainBubble = Color(0xFF1A2233);
  static const textPrimary = Color(0xFFE8EDF7);
  static const textMuted = Color(0xFF8C99B3);
}

ThemeData lainTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: LainColors.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: LainColors.primary,
    onPrimary: LainColors.onPrimary,
    surface: LainColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LainColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: LainColors.background,
      foregroundColor: LainColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: LainColors.textPrimary,
      ),
      bodyMedium: TextStyle(fontSize: 15, height: 1.45, color: LainColors.textPrimary),
      bodySmall: TextStyle(fontSize: 12, color: LainColors.textMuted),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: LainColors.surfaceHigh,
      hintStyle: TextStyle(color: LainColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
