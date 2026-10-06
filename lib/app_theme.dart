import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/app_layout.dart';

enum AppAppearance { system, light, dark, amoled }

enum AppColorSpec { spec2021, spec2025 }

const appKeyColors = [
  Color(0xfff44336),
  Color(0xffe91e63),
  Color(0xff9c27b0),
  Color(0xff673ab7),
  Color(0xff3f51b5),
  Color(0xff2196f3),
  Color(0xff00bcd4),
  Color(0xff009688),
  Color(0xff4faf50),
  Color(0xffffeb3b),
  Color(0xffffc107),
  Color(0xffff9800),
  Color(0xff795548),
  Color(0xff607d8f),
  Color(0xffff9ca8),
];
const appKeyColorNames = [
  '红色',
  '粉色',
  '紫色',
  '深紫',
  '靛青',
  '蓝色',
  '青色',
  '青绿',
  '绿色',
  '黄色',
  '琥珀',
  '橙色',
  '棕色',
  '灰蓝',
  '樱花',
];

String paletteStyleLabel(DynamicSchemeVariant value) => switch (value) {
  DynamicSchemeVariant.tonalSpot => 'TonalSpot',
  DynamicSchemeVariant.fruitSalad => 'FruitSalad',
  _ => '${value.name[0].toUpperCase()}${value.name.substring(1)}',
};

class AppTheme {
  static const defaultSeed = Color(0xff3f51b5);

  static SystemUiOverlayStyle systemBars(ColorScheme scheme) =>
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: scheme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: scheme.brightness,
        systemNavigationBarColor: scheme.surface,
        systemNavigationBarIconBrightness: scheme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      );

  static ColorScheme amoledScheme(ColorScheme scheme) => scheme.copyWith(
    surface: Colors.black,
    surfaceDim: Colors.black,
    surfaceBright: Colors.black,
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: Colors.black,
    surfaceContainer: Colors.black,
    surfaceContainerHigh: Colors.black,
    surfaceContainerHighest: Colors.black,
  );

  static ThemeData fromScheme(ColorScheme scheme) => ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: scheme.surface,
    ),
    cardTheme: _cardTheme,
    inputDecorationTheme: _inputTheme,
    listTileTheme: const ListTileThemeData(
      contentPadding: AppSpacing.controlInsets,
      horizontalTitleGap: AppSpacing.control,
      minVerticalPadding: AppSpacing.small,
    ),
    filledButtonTheme: FilledButtonThemeData(style: _buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _buttonStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: _buttonStyle),
    textButtonTheme: TextButtonThemeData(style: _buttonStyle),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
    ),
  );

  static const _buttonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(48, 48)),
    padding: WidgetStatePropertyAll(AppSpacing.controlInsets),
  );

  static const _cardTheme = CardThemeData(
    elevation: 0,
    margin: AppSpacing.cardMargin,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
    ),
  );
  static const _inputTheme = InputDecorationTheme(
    filled: true,
    contentPadding: AppSpacing.controlInsets,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide.none,
    ),
  );
}
