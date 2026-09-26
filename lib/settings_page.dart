import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'go_placement.dart';
import 'go_engine_manager.dart';
import 'go_model_manager.dart';
import 'about_licenses_page.dart';

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
