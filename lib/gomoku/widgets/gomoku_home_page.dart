import '../../ui/app_layout.dart';
import 'package:flutter/material.dart';

import '../../ai/widgets/ai_duel_setup.dart';
import '../../game_session.dart' show Side, SideX;
import '../gomoku_ai_level.dart';
import '../gomoku_session.dart';
import 'gomoku_game_page.dart';
import 'gomoku_ai_duel_page.dart';
import 'gomoku_library_page.dart';

class GomokuHomePage extends StatefulWidget {
  const GomokuHomePage({super.key, this.lanBuilder, this.rtcBuilder});

  final Widget Function(BuildContext, GomokuVariant)? lanBuilder;
  final Widget Function(BuildContext, GomokuVariant)? rtcBuilder;

  @override
  State<GomokuHomePage> createState() => _GomokuHomePageState();
}

class _GomokuHomePageState extends State<GomokuHomePage> {
  static const _variant = GomokuVariant.soosyrv8;

  Future<void> _open(Widget page) =>
      Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _startAi() async {
    var side = Side.black;
    var level = GomokuAiLevel.beginner;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('人机对弈'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Side>(
                  initialValue: side,
                  decoration: const InputDecoration(labelText: '开局执棋方（之后可交换）'),
                  items: [
                    for (final value in Side.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) => update(() => side = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<GomokuAiLevel>(
                  initialValue: level,
                  decoration: const InputDecoration(labelText: '难度'),
                  items: [
                    for (final value in GomokuAiLevel.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) => update(() => level = value!),
                ),
              ],
            ),
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
    await _open(
      GomokuGamePage(
        session: GomokuSession(variant: _variant),
        aiLevel: level,
        humanSide: side,
      ),
    );
  }

  Future<void> _startAiDuel() async {
    final config = await showAiDuelSetup(
      context: context,
      levels: GomokuAiLevel.values,
      initialLevel: GomokuAiLevel.intermediate,
      label: (level) => level.label,
    );
    if (config == null || !mounted) return;
    await _open(
      GomokuAiDuelPage(
        session: GomokuSession(variant: _variant),
        config: config,
      ),
    );
  }

  Widget _entry(
    String title,
    String description,
    IconData icon,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
        onTap: action,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('五子棋')),
    body: AppPageList(
      children: [
        Text('GOMOKU', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('15×15 · 索索夫-8'),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('26种指定开局 · 两次交换 · 五手1–8打\n黑方禁长连、四四、三三，禁手判负；五连优先获胜。'),
          ),
        ),
        const SizedBox(height: 16),
        _entry(
          '本地双人',
          '在同一设备上轮流落子',
          Icons.people_outline,
          () =>
              _open(GomokuGamePage(session: GomokuSession(variant: _variant))),
        ),
        _entry('人机对弈', 'Rapfi 三档难度及开局执棋方', Icons.smart_toy_outlined, _startAi),
        _entry(
          'AI 对抗',
          '两名 AI 自动对弈，暂停或单步观战',
          Icons.visibility_outlined,
          _startAiDuel,
        ),
        if (widget.lanBuilder != null)
          _entry(
            '联机对弈',
            '与朋友连接后对弈',
            Icons.wifi,
            () => _open(widget.lanBuilder!(context, _variant)),
          ),
        if (widget.rtcBuilder != null)
          _entry(
            '互联网联机',
            '通过 WebRTC 连接朋友',
            Icons.public,
            () => _open(widget.rtcBuilder!(context, _variant)),
          ),
        const SizedBox(height: 20),
        _entry(
          '棋谱库',
          '查看、继续对局，导出 SGF 或完整备份',
          Icons.collections_bookmark_outlined,
          () => _open(const GomokuLibraryPage()),
        ),
      ],
    ),
  );
}
