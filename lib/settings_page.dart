import 'package:flutter/material.dart';
import 'theme_controller.dart';
import 'theme_settings_page.dart';
import 'go_placement.dart';
import 'go_engine_manager.dart';
import 'go_model_manager.dart';
import 'about_licenses_page.dart';

class SettingsPage extends StatelessWidget {
  final ThemeController theme;
  const SettingsPage({super.key, required this.theme});

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
        Card(
          child: ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('主题设置'),
            subtitle: const Text('自定义更多主题选项'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ThemeSettingsPage(controller: theme),
              ),
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
            title: const Text('AI 引擎与模型'),
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
