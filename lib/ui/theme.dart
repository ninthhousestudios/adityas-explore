import 'package:flutter/material.dart';

const _lightBg = Color(0xFFF5F1EA);

ThemeData immersiveTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black54,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    iconTheme: const IconThemeData(color: Colors.white70),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white70),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xDD1A1520),
      textStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      elevation: 8,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6B4E9B),
      brightness: Brightness.dark,
    ),
  );
}

ThemeData lightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: _lightBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: _lightBg,
      foregroundColor: Colors.black87,
      elevation: 1,
    ),
    iconTheme: const IconThemeData(color: Colors.black54),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      elevation: 8,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6B4E9B),
      brightness: Brightness.light,
    ),
  );
}
