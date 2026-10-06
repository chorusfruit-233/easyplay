import '../../ui/app_layout.dart';
import 'package:flutter/material.dart';

import '../../game_session.dart' show Side, SideX;
import '../gomoku_ai_level.dart';
import '../gomoku_session.dart';
import '../gomoku_storage.dart';
import 'gomoku_game_page.dart';

class GomokuHomePage extends StatefulWidget {
  const GomokuHomePage({super.key, this.lanBuilder, this.rtcBuilder});

  final Widget Function(BuildContext, GomokuVariant)? lanBuilder;
  final Widget Function(BuildContext, GomokuVariant)? rtcBuilder;

  @override
  State<GomokuHomePage> createState() => _GomokuHomePageState();
}

class _GomokuHomePageState extends State<GomokuHomePage> {
  late Future<List<GomokuRecord>> _records = GomokuStorage.list();
  GomokuVariant _variant = GomokuVariant.freestyle;

  void _reload() {
    if (mounted) {
      setState(() {
        _records = GomokuStorage.list();
      });
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    _reload();
  }

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
                  decoration: const InputDecoration(labelText: '执棋方'),
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

  void _restore(GomokuRecord record) {
    try {
      _open(
        GomokuGamePage(
          session: record.restore(),
          recordId: record.id,
          createdAt: record.createdAt,
          aiLevel: record.aiLevel,
          humanSide: record.humanSide,
        ),
      );
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法恢复对局：$error')));
    }
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
        const Text('15×15 · 黑方先行 · 选择双方使用的规则'),
        const SizedBox(height: 16),
        DropdownButtonFormField<GomokuVariant>(
          initialValue: _variant,
          decoration: const InputDecoration(labelText: '规则'),
          items: [
            for (final variant in GomokuVariant.values)
              DropdownMenuItem(value: variant, child: Text(variant.label)),
          ],
          onChanged: (value) => setState(() => _variant = value!),
        ),
        const SizedBox(height: 8),
        Text(_variant.description),
        if (_variant == GomokuVariant.renju)
          const Text('采用自由开局，不含交换开局流程；黑方禁手会被拒绝并显示原因。'),
        const SizedBox(height: 24),
        _entry(
          '本地双人',
          '在同一设备上轮流落子',
          Icons.people_outline,
          () =>
              _open(GomokuGamePage(session: GomokuSession(variant: _variant))),
        ),
        _entry('人机对弈', '选择初级、中级或高级及执棋方', Icons.smart_toy_outlined, _startAi),
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
        Text('最近对局', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        FutureBuilder<List<GomokuRecord>>(
          future: _records,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return ListTile(
                title: const Text('无法读取存档'),
                trailing: TextButton(
                  onPressed: _reload,
                  child: const Text('重试'),
                ),
              );
            }
            final records = snapshot.data ?? [];
            if (records.isEmpty) return const Text('还没有保存的五子棋对局');
            return Column(
              children: [
                for (final record in records.take(20))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(
                          '${record.variant.label} · ${record.moveCount} 手',
                        ),
                        subtitle: Text(
                          '${record.aiLevel == null ? '本地双人' : '人机 · ${record.aiLevel!.label}'} · ${record.gameOver ? record.resultLabel : '继续对局'} · ${record.createdAt.toLocal().toString().split('.').first}',
                        ),
                        onTap: () => _restore(record),
                        trailing: IconButton(
                          tooltip: '删除存档',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            try {
                              await GomokuStorage.delete(record.id);
                              _reload();
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('删除失败：$error')),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
