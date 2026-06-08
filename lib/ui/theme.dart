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
    popupMenuTheme: const PopupMenuThemeData(
      color: Color(0xDD1A1520),
      textStyle: TextStyle(color: Colors.white),
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
    popupMenuTheme: const PopupMenuThemeData(
      color: Colors.white,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6B4E9B),
      brightness: Brightness.light,
    ),
  );
}
