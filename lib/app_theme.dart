import 'package:flutter/material.dart';

enum AppAppearance { system, light, dark }

class AppTheme {
  static const defaultSeed = Color(0xff3f51b5);

  static ThemeData light({
    required Color seed,
    required DynamicSchemeVariant paletteStyle,
  }) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      dynamicSchemeVariant: paletteStyle,
      brightness: Brightness.light,
      contrastLevel: 0.05,
    ),
    scaffoldBackgroundColor: const Color(0xfff8f8fc),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: _cardTheme,
    inputDecorationTheme: _inputTheme,
  );

  static ThemeData dark({
    required Color seed,
    required DynamicSchemeVariant paletteStyle,
    required bool amoled,
  }) {
    var scheme = ColorScheme.fromSeed(
      seedColor: seed,
      dynamicSchemeVariant: paletteStyle,
      brightness: Brightness.dark,
      contrastLevel: 0.05,
    );
    if (amoled) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceDim: Colors.black,
        surfaceBright: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: Colors.black,
        surfaceContainer: Colors.black,
        surfaceContainerHigh: Colors.black,
        surfaceContainerHighest: Colors.black,
      );
    }
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: amoled ? Colors.black : const Color(0xff101116),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      cardTheme: _cardTheme,
      inputDecorationTheme: _inputTheme,
    );
  }

  static const _cardTheme = CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
    ),
  );
  static const _inputTheme = InputDecorationTheme(
    filled: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide.none,
    ),
  );
}
