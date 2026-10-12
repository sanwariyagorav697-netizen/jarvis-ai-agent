import 'package:flutter/material.dart';

/// JARVIS-inspired HUD palette. Dark base + blue/cyan accents.
/// Koi proprietary movie asset nahi — sab colors/shapes khud banaye hain.
abstract final class JarvisPalette {

  static const Color background = Color(0xFF050B16);
  static const Color panel = Color(0xFF0B1B2B);
  static const Color panelSoft = Color(0xFF10253A);
  static const Color gridLine = Color(0xFF163A5A);
  static const Color cyan = Color(0xFF7FF9FF);
  static const Color blue = Color(0xFF2FA8FF);
  static const Color success = Color(0xFF5BFFB4);
  static const Color warning = Color(0xFFFFC46B);
  static const Color error = Color(0xFFFF6B7A);
  static const Color dimText = Color(0xFF8FB6D9);
}

ThemeData buildJarvisTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: JarvisPalette.blue,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: JarvisPalette.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF071B30),
      foregroundColor: JarvisPalette.cyan,
      centerTitle: true,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: JarvisPalette.cyan,
        fontSize: 19,
        letterSpacing: 5,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: JarvisPalette.gridLine,
      thickness: 1,
      space: 12,
    ),
    iconTheme: const IconThemeData(color: JarvisPalette.cyan),
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFE6F6FF),
          displayColor: JarvisPalette.cyan,
        ),
  );
}

/// Ek patla border + halka fill — HUD panels ke liye reusable decoration.
BoxDecoration jarvisPanel({
  Color borderColor = JarvisPalette.gridLine,
  Color fillColor = JarvisPalette.panel,
  double radius = 18,
}) {
  return BoxDecoration(
    color: fillColor,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor, width: 1),
  );
}
