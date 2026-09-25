import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_session.dart';
import 'game_page.dart';
import 'games/go_game.dart';
import 'go_model_manager.dart';
import 'go_engine_manager.dart';

export 'board.dart';
export 'game_page.dart';

void main() => runApp(const EasyPlayApp());

enum AppAppearance { system, light, dark, monet }

class EasyPlayApp extends StatefulWidget {
  const EasyPlayApp({super.key});
  @override
  State<EasyPlayApp> createState() => _EasyPlayAppState();
}

class _EasyPlayAppState extends State<EasyPlayApp> {
  AppAppearance _appearance = AppAppearance.system;
  Color? _monetSeed;

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
      if (!mounted) return;
      setState(
        () => _appearance = AppAppearance.values.firstWhere(
          (item) => item.name == value,
          orElse: () => AppAppearance.system,
        ),
      );
    });
  }

  Future<void> _setAppearance(AppAppearance value) async {
    setState(() => _appearance = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance', value.name);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EasyPlay',
    debugShowCheckedModeBanner: false,
    themeMode: switch (_appearance) {
      AppAppearance.system => ThemeMode.system,
      AppAppearance.light => ThemeMode.light,
      AppAppearance.dark => ThemeMode.dark,
      AppAppearance.monet => ThemeMode.system,
    },
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _appearance == AppAppearance.monet
            ? (_monetSeed ?? _keyColor)
            : _keyColor,
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
      colorScheme: ColorScheme.fromSeed(
        seedColor: _appearance == AppAppearance.monet
            ? (_monetSeed ?? _keyColor)
            : _keyColor,
        brightness: Brightness.dark,
        contrastLevel: 0.05,
      ),
      scaffoldBackgroundColor: const Color(0xff101116),
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
    home: Shell(appearance: _appearance, onAppearanceChanged: _setAppearance),
  );
}

class Shell extends StatefulWidget {
  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  const Shell({
    super.key,
    required this.appearance,
    required this.onAppearanceChanged,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    type.icon,
                    color: active
                        ? colors.onPrimaryContainer
                        : available
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    size: 28,
                  ),
                  const Spacer(),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.label,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: active
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    type.description,
                    style: TextStyle(
                      color: active
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
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

class SettingsPage extends StatelessWidget {
  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onAppearanceChanged;
  const SettingsPage({
    super.key,
    required this.appearance,
    required this.onAppearanceChanged,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<AppAppearance>(
              segments: const [
                ButtonSegment(
                  value: AppAppearance.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('系统'),
                ),
                ButtonSegment(
                  value: AppAppearance.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: AppAppearance.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('深色'),
                ),
                ButtonSegment(
                  value: AppAppearance.monet,
                  icon: Icon(Icons.palette_outlined),
                  label: Text('动态色'),
                ),
              ],
              selected: {appearance},
              onSelectionChanged: (values) => onAppearanceChanged(values.first),
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
        const SizedBox(height: 28),
        Text(
          '关于',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于 EasyPlay'),
            subtitle: const Text('版本信息与开源组件许可证'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutLicensesPage()),
            ),
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
