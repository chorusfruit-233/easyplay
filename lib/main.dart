import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_session.dart';
import 'game_page.dart';
import 'games/go_game.dart';
import 'go_model_manager.dart';
import 'go_engine_manager.dart';
import 'go_placement.dart';

export 'board.dart';
export 'game_page.dart';

void main() => runApp(const EasyPlayApp());

enum AppAppearance { system, light, dark }

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
  static const _keyColor = Color(0xff3f51b5);

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

  ColorScheme _darkScheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _keyColorOverride ?? _monetSeed ?? _keyColor,
      dynamicSchemeVariant: _paletteStyle,
      brightness: Brightness.dark,
      contrastLevel: 0.05,
    );
    if (!_amoled) return scheme;
    return scheme.copyWith(
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

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EasyPlay',
    debugShowCheckedModeBanner: false,
    themeMode: switch (_appearance) {
      AppAppearance.system => ThemeMode.system,
      AppAppearance.light => ThemeMode.light,
      AppAppearance.dark => ThemeMode.dark,
    },
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _keyColorOverride ?? _monetSeed ?? _keyColor,
        dynamicSchemeVariant: _paletteStyle,
        brightness: Brightness.light,
        contrastLevel: 0.05,
      ),
      scaffoldBackgroundColor: const Color(0xfff8f8fc),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: _darkScheme(),
      scaffoldBackgroundColor: _amoled ? Colors.black : const Color(0xff101116),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide.none,
        ),
      ),
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

class _ThemeModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  const _ThemeModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => ChoiceChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    selected: selected,
    onSelected: (_) => onPressed(),
  );
}

class _ColorChoice extends StatelessWidget {
  final Color? color;
  final bool selected;
  final String tooltip;
  final VoidCallback onPressed;
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color ?? scheme.primaryContainer,
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: color == null
              ? Icon(
                  Icons.auto_awesome,
                  size: 19,
                  color: scheme.onPrimaryContainer,
                )
              : selected
              ? Icon(Icons.check, size: 19, color: _onColor(color!))
              : null,
        ),
      ),
    );
  }
}

Color _onColor(Color color) =>
    color.computeLuminance() > 0.45 ? Colors.black : Colors.white;

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.palette_outlined, color: colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Material 3 主题预览',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '主色、容器色和表面色会随设置即时更新。',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 18,
              height: 52,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  final Color? keyColor;
  final DynamicSchemeVariant paletteStyle;
  final bool amoled;
  final ValueChanged<Color?> onThemeColorChanged;
  final ValueChanged<DynamicSchemeVariant> onPaletteStyleChanged;
  final ValueChanged<bool> onAmoledChanged;
  const SettingsPage({
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('设置'),
      actions: [
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AboutLicensesPage()),
          ),
          child: const Text('关于 EasyPlay'),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '外观显示',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '选择 EasyPlay 的颜色主题。系统模式会跟随设备设置。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        const _ThemePreviewCard(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ThemeModeChip(
                  label: '系统',
                  icon: Icons.brightness_auto_outlined,
                  selected: appearance == AppAppearance.system,
                  onPressed: () => onAppearanceChanged(AppAppearance.system),
                ),
                _ThemeModeChip(
                  label: '浅色',
                  icon: Icons.light_mode_outlined,
                  selected: appearance == AppAppearance.light,
                  onPressed: () => onAppearanceChanged(AppAppearance.light),
                ),
                _ThemeModeChip(
                  label: '深色',
                  icon: Icons.dark_mode_outlined,
                  selected: appearance == AppAppearance.dark,
                  onPressed: () => onAppearanceChanged(AppAppearance.dark),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.brightness_1_outlined),
            title: const Text('AMOLED 纯黑'),
            subtitle: const Text('仅在深色模式下使用纯黑背景，适合 OLED 屏幕'),
            value: amoled,
            onChanged: onAmoledChanged,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('强调色', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '动态色会读取 Android 12 及以上系统的壁纸配色。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _ColorChoice(
                      color: null,
                      selected: keyColor == null,
                      tooltip: '动态色',
                      onPressed: () => onThemeColorChanged(null),
                    ),
                    for (final color in const [
                      Color(0xfff44336),
                      Color(0xffe91e63),
                      Color(0xff9c27b0),
                      Color(0xff673ab7),
                      Color(0xff3f51b5),
                      Color(0xff2196f3),
                      Color(0xff00bcd4),
                      Color(0xff009688),
                      Color(0xff4caf50),
                      Color(0xffffeb3b),
                      Color(0xffffc107),
                      Color(0xffff9800),
                      Color(0xff795548),
                      Color(0xff607d8f),
                      Color(0xffff9ca8),
                    ])
                      _ColorChoice(
                        color: color,
                        selected: keyColor?.toARGB32() == color.toARGB32(),
                        tooltip: '强调色',
                        onPressed: () => onThemeColorChanged(color),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: DropdownButtonFormField<DynamicSchemeVariant>(
              initialValue: paletteStyle,
              decoration: const InputDecoration(labelText: '调色板风格'),
              onChanged: (value) {
                if (value != null) onPaletteStyleChanged(value);
              },
              items: const [
                DropdownMenuItem(
                  value: DynamicSchemeVariant.tonalSpot,
                  child: Text('Tonal Spot · 柔和'),
                ),
                DropdownMenuItem(
                  value: DynamicSchemeVariant.neutral,
                  child: Text('Neutral · 中性'),
                ),
                DropdownMenuItem(
                  value: DynamicSchemeVariant.vibrant,
                  child: Text('Vibrant · 鲜明'),
                ),
                DropdownMenuItem(
                  value: DynamicSchemeVariant.expressive,
                  child: Text('Expressive · 表现力'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Card(
          child: ListTile(
            leading: const Icon(Icons.touch_app_outlined),
            title: const Text('落子模式'),
            subtitle: const Text('选择围棋棋盘的点击、预览和确认方式'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const GoPlacementSettingsPage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          '围棋 AI',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('AI 引擎配置'),
            subtitle: const Text('管理 KataGo 配置、思考时间、线程与高级参数'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GoEngineManagerPage()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: const Text('KataGo 引擎与模型'),
            subtitle: const Text('选择模型，导入或下载 KataGo 网络'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GoModelManagerPage()),
            ),
          ),
        ),
      ],
    ),
  );
}

class GoPlacementSettingsPage extends StatefulWidget {
  const GoPlacementSettingsPage({super.key});

  @override
  State<GoPlacementSettingsPage> createState() =>
      _GoPlacementSettingsPageState();
}

class _GoPlacementSettingsPageState extends State<GoPlacementSettingsPage> {
  GoPlacementMode? _mode;

  @override
  void initState() {
    super.initState();
    GoPlacementPreferences.load().then((value) {
      if (mounted) setState(() => _mode = value);
    });
  }

  Future<void> _select(GoPlacementMode value) async {
    setState(() => _mode = value);
    await GoPlacementPreferences.save(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('落子模式设置')),
    body: _mode == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: RadioGroup<GoPlacementMode>(
                  groupValue: _mode,
                  onChanged: (value) {
                    if (value != null) _select(value);
                  },
                  child: Column(
                    children: [
                      for (final mode in GoPlacementMode.values)
                        RadioListTile<GoPlacementMode>(
                          value: mode,
                          title: Text(mode.label),
                          subtitle: Text(mode.description),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '选择会保存在本机，并应用于之后开始的围棋对局。自动模式会根据棋盘在屏幕上的网格大小选择直接落子或二次确认。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
  );
}

class _LicenseEntry {
  final String name;
  final String asset;
  const _LicenseEntry(this.name, this.asset);
}

const _licenseEntries = <_LicenseEntry>[
  _LicenseEntry('EasyPlay（本项目）', 'assets/licenses/GPL-3.0.txt'),
  _LicenseEntry('KataGo', 'assets/katago/KATAGO-LICENSE.txt'),
  _LicenseEntry('KataGo 神经网络模型', 'assets/katago/MODEL-LICENSE.txt'),
  _LicenseEntry('Eigen', 'assets/katago/EIGEN-LICENSE.txt'),
  _LicenseEntry('Apache License 2.0', 'assets/katago/COPYING.APACHE'),
  _LicenseEntry('BSD License', 'assets/katago/COPYING.BSD'),
  _LicenseEntry('GPL License', 'assets/katago/COPYING.GPL'),
  _LicenseEntry('LGPL License', 'assets/katago/COPYING.LGPL'),
  _LicenseEntry('Minpack License', 'assets/katago/COPYING.MINPACK'),
  _LicenseEntry('MPL 2.0', 'assets/katago/COPYING.MPL2'),
  _LicenseEntry('第三方组件许可证说明', 'assets/katago/COPYING.README'),
  _LicenseEntry(
    'clblast',
    'assets/katago/THIRD-PARTY-LICENSES/clblast/LICENSE',
  ),
  _LicenseEntry(
    'filesystem',
    'assets/katago/THIRD-PARTY-LICENSES/filesystem-1.5.8/LICENSE',
  ),
  _LicenseEntry(
    'half',
    'assets/katago/THIRD-PARTY-LICENSES/half-2.2.0/LICENSE.txt',
  ),
  _LicenseEntry(
    'cpp-httplib',
    'assets/katago/THIRD-PARTY-LICENSES/httplib/LICENSE',
  ),
  _LicenseEntry(
    'tclap',
    'assets/katago/THIRD-PARTY-LICENSES/tclap-1.2.5/COPYING',
  ),
  _LicenseEntry(
    'KataGo CoreML',
    'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/LICENSE',
  ),
  _LicenseEntry(
    'KataGo CoreML NOTICE',
    'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/NOTICE',
  ),
  _LicenseEntry(
    'macOS components',
    'assets/katago/THIRD-PARTY-LICENSES/macos/LICENSE',
  ),
  _LicenseEntry(
    'Mozilla CA certificates',
    'assets/katago/THIRD-PARTY-LICENSES/mozilla-cacerts/LICENSE',
  ),
];

class AboutLicensesPage extends StatelessWidget {
  const AboutLicensesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于与许可证')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.blur_on)),
            title: const Text('EasyPlay'),
            subtitle: const Text('围棋 · 本地对局\nGPL-3.0 授权，使用 KataGo 及多个开源组件'),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '开源许可证',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        ..._licenseEntries.map(
          (entry) => Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(entry.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _LicenseTextPage(entry: entry),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'EasyPlay'),
          icon: const Icon(Icons.article_outlined),
          label: const Text('查看 Flutter 依赖许可证'),
        ),
      ],
    ),
  );
}

class _LicenseTextPage extends StatelessWidget {
  final _LicenseEntry entry;
  const _LicenseTextPage({required this.entry});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(entry.name)),
    body: FutureBuilder<String>(
      future: rootBundle.loadString(entry.asset),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('许可证文件读取失败'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              snapshot.data!,
              style: const TextStyle(fontFamily: 'monospace', height: 1.45),
            ),
          ),
        );
      },
    ),
  );
}
