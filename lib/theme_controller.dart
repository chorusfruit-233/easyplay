import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'material_colors_platform.dart';
import 'material_scheme_decoder.dart';

/// The root app and pushed settings routes observe the same live preferences.
class ThemeController extends ChangeNotifier {
  AppAppearance appearance = AppAppearance.system;
  Color? keyColor;
  Color lightSystemSeed = AppTheme.defaultSeed;
  Color darkSystemSeed = AppTheme.defaultSeed;
  DynamicSchemeVariant paletteStyle = DynamicSchemeVariant.tonalSpot;
  AppColorSpec colorSpec = AppColorSpec.spec2025;
  double pageScale = 1;
  Map<int, ColorScheme> lightSchemes = {}, darkSchemes = {};
  String? error;
  bool _disposed = false;
  int _generation = 0;
  final Map<String, List<ColorScheme>> _cache = {};

  ThemeMode get mode => switch (appearance) {
    AppAppearance.system => ThemeMode.system,
    AppAppearance.light => ThemeMode.light,
    AppAppearance.dark || AppAppearance.amoled => ThemeMode.dark,
  };
  bool get amoled => appearance == AppAppearance.amoled;
  ColorScheme scheme({required bool dark, Color? color}) {
    final seed = color ?? (dark ? darkSystemSeed : lightSystemSeed);
    final generated = (dark ? darkSchemes : lightSchemes)[seed.toARGB32()];
    var value =
        generated ??
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: dark ? Brightness.dark : Brightness.light,
          dynamicSchemeVariant: paletteStyle,
        );
    if (dark && amoled) value = AppTheme.amoledScheme(value);
    return value;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    final saved = prefs.getString('appearance');
    // Old AMOLED was a switch; migrate it into KernelSU's forced-dark mode.
    appearance = prefs.getBool('theme_amoled') == true || saved == 'amoled'
        ? AppAppearance.amoled
        : AppAppearance.values.firstWhere(
            (v) => v.name == saved,
            orElse: () => AppAppearance.system,
          );
    final seed = prefs.getInt('theme_key_color');
    keyColor = seed == null || seed == 0 ? null : Color(seed);
    paletteStyle = DynamicSchemeVariant.values.firstWhere(
      (v) => v.name == prefs.getString('theme_palette_style'),
      orElse: () => DynamicSchemeVariant.tonalSpot,
    );
    colorSpec = AppColorSpec.values.firstWhere(
      (v) => v.name == prefs.getString('theme_color_spec'),
      orElse: () => AppColorSpec.spec2025,
    );
    pageScale = (prefs.getDouble('theme_page_scale') ?? 1).clamp(0.8, 1.1);
    notifyListeners();
    await updateSystemColors();
  }

  Future<void> updateSystemColors() async {
    try {
      final palette = await DynamicColorPlugin.getCorePalette();
      if (_disposed) return;
      if (palette != null) {
        lightSystemSeed = Color(palette.primary.get(40));
        darkSystemSeed = Color(palette.primary.get(80));
      }
    } catch (_) {
      /* Platforms without a wallpaper palette use the default seed. */
    }
    if (!_disposed) await refresh();
  }

  Future<void> setAppearance(AppAppearance value) async {
    appearance = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance', value.name);
    await prefs.remove('theme_amoled');
  }

  Future<void> setColor(Color? value) async {
    keyColor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_key_color', value?.toARGB32() ?? 0);
    await refresh();
  }

  Future<void> setStyle(DynamicSchemeVariant value) async {
    paletteStyle = value;
    await _saveAndRefresh('theme_palette_style', value.name);
  }

  Future<void> setSpec(AppColorSpec value) async {
    colorSpec = value;
    await _saveAndRefresh('theme_color_spec', value.name);
  }

  Future<void> setScale(double value) async {
    pageScale = value.clamp(0.8, 1.1);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('theme_page_scale', pageScale);
  }

  Future<void> _saveAndRefresh(String key, String value) async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    await refresh();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    final style = paletteStyle, spec = colorSpec;
    final seeds = {
      lightSystemSeed.toARGB32(),
      darkSystemSeed.toARGB32(),
      if (keyColor != null) keyColor!.toARGB32(),
      ...appKeyColors.map((c) => c.toARGB32()),
    }.toList();
    try {
      Future<Map<int, ColorScheme>> build(bool dark) async {
        final cacheKey = '${style.name}/${spec.name}/$dark/${seeds.join(',')}';
        var rows = _cache[cacheKey];
        if (rows == null) {
          try {
            rows =
                (await generateMaterialColors({
                      'seeds': seeds,
                      'style': style.name,
                      'spec': spec.name,
                      'dark': dark,
                    }))
                    .map(
                      (r) => decodeMaterialScheme(
                        r as Map,
                        dark ? Brightness.dark : Brightness.light,
                      ),
                    )
                    .toList();
          } on MissingPluginException {
            // Linux and widget tests have no native color bridge.
            rows = seeds
                .map(
                  (s) => ColorScheme.fromSeed(
                    seedColor: Color(s),
                    brightness: dark ? Brightness.dark : Brightness.light,
                    dynamicSchemeVariant: style,
                  ),
                )
                .toList();
          }
          if (rows.length != seeds.length) throw StateError('配色结果数量不匹配');
          if (_cache.length > 20) _cache.clear();
          _cache[cacheKey] = rows;
        }
        return Map.fromIterables(seeds, rows);
      }

      final results = await Future.wait([build(false), build(true)]);
      if (_disposed || generation != _generation) return;
      lightSchemes = results[0];
      darkSchemes = results[1];
      error = null;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = '主题配色加载失败，暂用内置配色；请重试';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
