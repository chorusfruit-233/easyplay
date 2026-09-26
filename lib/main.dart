import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_session.dart';
import 'game_page.dart';
import 'games/go_game.dart';
import 'app_theme.dart';
import 'settings_page.dart';

export 'board.dart';
export 'game_page.dart';

void main() => runApp(const EasyPlayApp());

class EasyPlayApp extends StatefulWidget {
  const EasyPlayApp({super.key});
  @override
  State<EasyPlayApp> createState() => _EasyPlayAppState();
}

class _EasyPlayAppState extends State<EasyPlayApp> {
  AppAppearance _appearance = AppAppearance.system;
  Color? _monetSeed;
  Color? _keyColorOverride;
  DynamicSchemeVariant _paletteStyle = DynamicSchemeVariant.tonalSpot;
  bool _amoled = false;

  // Indigo is one of KernelSU's key-colour presets. Generate Material tonal
  // roles from the same seed in both brightness modes.

  @override
  void initState() {
    super.initState();
    DynamicColorPlugin.getCorePalette().then((palette) {
      if (!mounted || palette == null) return;
      setState(() => _monetSeed = Color(palette.primary.get(40)));
    });
    SharedPreferences.getInstance().then((prefs) {
      final value = prefs.getString('appearance');
      final savedColor = prefs.getInt('theme_key_color');
      final savedStyle = prefs.getString('theme_palette_style');
      if (!mounted) return;
      setState(() {
        _appearance = value == 'monet' || value == 'amoled'
            ? AppAppearance.system
            : AppAppearance.values.firstWhere(
                (item) => item.name == value,
                orElse: () => AppAppearance.system,
              );
        _amoled = prefs.getBool('theme_amoled') ?? value == 'amoled';
        _keyColorOverride = savedColor == null || savedColor == 0
            ? null
            : Color(savedColor);
        _paletteStyle = DynamicSchemeVariant.values.firstWhere(
          (item) => item.name == savedStyle,
          orElse: () => DynamicSchemeVariant.tonalSpot,
        );
      });
    });
  }

  Future<void> _setAppearance(AppAppearance value) async {
    setState(() => _appearance = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance', value.name);
  }

  Future<void> _setThemeColor(Color? color) async {
    setState(() => _keyColorOverride = color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_key_color', color?.toARGB32() ?? 0);
  }

  Future<void> _setPaletteStyle(DynamicSchemeVariant value) async {
    setState(() => _paletteStyle = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_palette_style', value.name);
  }

  Future<void> _setAmoled(bool value) async {
    setState(() => _amoled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme_amoled', value);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EasyPlay',
    debugShowCheckedModeBanner: false,
    themeMode: switch (_appearance) {
      AppAppearance.system => ThemeMode.system,
      AppAppearance.light => ThemeMode.light,
      AppAppearance.dark => ThemeMode.dark,
    },
    theme: AppTheme.light(
      seed: _keyColorOverride ?? _monetSeed ?? AppTheme.defaultSeed,
      paletteStyle: _paletteStyle,
    ),
    darkTheme: AppTheme.dark(
      seed: _keyColorOverride ?? _monetSeed ?? AppTheme.defaultSeed,
      paletteStyle: _paletteStyle,
      amoled: _amoled,
    ),
    home: Shell(
      appearance: _appearance,
      onAppearanceChanged: _setAppearance,
      keyColor: _keyColorOverride,
      paletteStyle: _paletteStyle,
      amoled: _amoled,
      onThemeColorChanged: _setThemeColor,
      onPaletteStyleChanged: _setPaletteStyle,
      onAmoledChanged: _setAmoled,
    ),
  );
}

class Shell extends StatefulWidget {
  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final Color? keyColor;
  final DynamicSchemeVariant paletteStyle;
  final bool amoled;
  final ValueChanged<Color?> onThemeColorChanged;
  final ValueChanged<DynamicSchemeVariant> onPaletteStyleChanged;
  final ValueChanged<bool> onAmoledChanged;
  const Shell({
    super.key,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.keyColor,
    required this.paletteStyle,
    required this.amoled,
    required this.onThemeColorChanged,
    required this.onPaletteStyleChanged,
    required this.onAmoledChanged,
  });
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  GameType selected = GameType.go;

  void _openGame(GameType game) {
    if (game != GameType.go) return;
    setState(() => selected = game);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GoGamePage()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: HomePage(
        onPlay: _openGame,
        selected: selected,
        onSettings: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SettingsPage(
              appearance: widget.appearance,
              onAppearanceChanged: widget.onAppearanceChanged,
              keyColor: widget.keyColor,
              paletteStyle: widget.paletteStyle,
              amoled: widget.amoled,
              onThemeColorChanged: widget.onThemeColorChanged,
              onPaletteStyleChanged: widget.onPaletteStyleChanged,
              onAmoledChanged: widget.onAmoledChanged,
            ),
          ),
        ),
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  final ValueChanged<GameType> onPlay;
  final GameType selected;
  final VoidCallback onSettings;
  const HomePage({
    super.key,
    required this.onPlay,
    required this.selected,
    required this.onSettings,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth > 760;
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.blur_on,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'EASYPLAY',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        fontSize: 19,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onSettings,
                      tooltip: '设置',
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Text(
                  '今天，\n来一局好棋。',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '从围棋开始，专注每一步棋。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                GridView.count(
                  crossAxisCount: wide ? 3 : 1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: wide ? 1.5 : 2.25,
                  children: GameType.values
                      .map(
                        (g) => GameCard(
                          type: g,
                          selected: selected == g,
                          onTap: g == GameType.go ? () => onPlay(g) : null,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '新对局',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const ContinueCard(),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class GameCard extends StatelessWidget {
  final GameType type;
  final bool selected;
  final VoidCallback? onTap;
  const GameCard({
    super.key,
    required this.type,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final available = type == GameType.go;
    final active = selected && available;
    final colors = Theme.of(context).colorScheme;
    // Deliberately not an InkWell/Ink pair.
    //
    // With the ink pair in place the card did not react to the Material 3
    // stretch overscroll effect while the surrounding text did. Removing it
    // fixes that, confirmed on device: debugPaintLayerBordersEnabled showed the
    // card owning a compositing layer that the text did not have, and the card
    // began stretching once the pair was replaced. Verified by elimination that
    // neither borderRadius nor boxShadow is responsible, so both stay below.
    //
    // The mechanism is not fully established. The working theory is that the
    // ink features create a separate layer the shader-based stretch
    // ImageFilter does not reach; what is established is that this widget
    // structure behaves correctly on device.
    //
    // Trade-off: no ripple on tap. Add a pressed-state animation here rather
    // than going back to InkWell if that feedback is wanted.
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [colors.primaryContainer, colors.primaryContainer]
                : available
                ? [colors.surface, colors.surfaceContainerLowest]
                : [colors.surfaceContainerHigh, colors.surfaceContainer],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                type.icon,
                color: active
                    ? colors.onPrimaryContainer
                    : available
                    ? colors.primary
                    : colors.onSurfaceVariant,
                size: 30,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: active
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (available)
                Icon(
                  Icons.arrow_outward,
                  color: active
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '未完成',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key});
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: ListTile(
      contentPadding: const EdgeInsets.all(14),
      leading: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.blur_on,
          color: Theme.of(context).colorScheme.onTertiaryContainer,
          size: 31,
        ),
      ),
      title: const Text(
        '开始新对局 · 19 路围棋',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: const Text('开始一盘新的围棋对局'),
      trailing: FilledButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GoGamePage()),
        ),
        child: const Text('开始'),
      ),
    ),
  );
}
