import '../../ui/app_layout.dart';
import 'package:flutter/material.dart';

import '../../ai/widgets/ai_duel_setup.dart';
import '../../game_session.dart' show Side, SideX;
import '../draughts_ai_level.dart';
import '../draughts_rules.dart';
import '../draughts_session.dart';
import '../draughts_variant.dart';
import 'draughts_game_page.dart';
import 'draughts_lan_pages.dart';
import 'draughts_ai_duel_page.dart';
import 'draughts_library_page.dart';

class DraughtsNewGamePage extends StatefulWidget {
  const DraughtsNewGamePage({super.key});
  @override
  State<DraughtsNewGamePage> createState() => _DraughtsNewGamePageState();
}

class _DraughtsNewGamePageState extends State<DraughtsNewGamePage> {
  DraughtsVariant _selected = DraughtsVariant.english;
  void _start() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => DraughtsGamePage(
        session: DraughtsSession(DraughtsRules.forVariant(_selected)),
      ),
    ),
  );

  Future<void> _startAi() async {
    var side = DraughtsRules.forVariant(_selected).firstMove;
    var level = DraughtsAiLevel.intermediate;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('人机对弈'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Side>(
                initialValue: side,
                decoration: const InputDecoration(labelText: '执棋方'),
                items: [
                  for (final s in Side.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (value) => update(() => side = value!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<DraughtsAiLevel>(
                initialValue: level,
                decoration: const InputDecoration(labelText: '难度'),
                items: [
                  for (final l in DraughtsAiLevel.values)
                    DropdownMenuItem(value: l, child: Text(l.label)),
                ],
                onChanged: (value) => update(() => level = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始对局'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DraughtsGamePage(
          session: DraughtsSession(DraughtsRules.forVariant(_selected)),
          aiLevel: level,
          humanSide: side,
        ),
      ),
    );
  }

  Future<void> _startAiDuel() async {
    final config = await showAiDuelSetup(
      context: context,
      levels: DraughtsAiLevel.values,
      initialLevel: DraughtsAiLevel.intermediate,
      label: (level) => level.label,
    );
    if (config == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DraughtsAiDuelPage(
          session: DraughtsSession(DraughtsRules.forVariant(_selected)),
          config: config,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Checkers / Draughts')),
    body: AppPageList(
      children: [
        Text(
          '选择规则',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '各种规则各有不同的棋盘、吃子和升王方式。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        for (final variant in DraughtsVariant.values)
          Card(
            color: _selected == variant
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            child: ListTile(
              leading: Icon(
                _selected == variant
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(
                variant.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(DraughtsVariantInfo.of(variant).summary),
              trailing: IconButton(
                tooltip: '规则说明',
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showRules(variant),
              ),
              onTap: () => setState(() => _selected = variant),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('本地双人对局'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _startAi,
          icon: const Icon(Icons.smart_toy_outlined),
          label: const Text('人机对弈'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _startAiDuel,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('AI 对抗'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => DraughtsLanLobbyPage(variant: _selected),
            ),
          ),
          icon: const Icon(Icons.wifi),
          label: const Text('局域网联机'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const DraughtsLibraryPage()),
          ),
          icon: const Icon(Icons.collections_bookmark_outlined),
          label: const Text('棋谱库'),
        ),
      ],
    ),
  );

  void _showRules(DraughtsVariant variant) {
    final info = DraughtsVariantInfo.of(variant);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(variant.label),
        content: SingleChildScrollView(
          child: Text('${info.name}\n\n${info.details}\n连续吃子作为一手提交。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
