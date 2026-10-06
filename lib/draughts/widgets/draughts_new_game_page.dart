import '../../ui/app_layout.dart';
import 'package:flutter/material.dart';

import '../../game_session.dart' show Side, SideX;
import '../draughts_ai_level.dart';
import '../draughts_record.dart';
import '../draughts_notation.dart';
import '../draughts_rules.dart';
import '../draughts_session.dart';
import '../draughts_storage.dart';
import '../draughts_variant.dart';
import 'draughts_game_page.dart';
import 'draughts_lan_pages.dart';

class DraughtsNewGamePage extends StatefulWidget {
  const DraughtsNewGamePage({super.key});
  @override
  State<DraughtsNewGamePage> createState() => _DraughtsNewGamePageState();
}

class _DraughtsNewGamePageState extends State<DraughtsNewGamePage> {
  DraughtsVariant _selected = DraughtsVariant.english;
  late Future<List<DraughtsRecord>> _records = DraughtsStorage.list();

  void _reloadRecords() {
    if (!mounted) return;
    setState(() {
      _records = DraughtsStorage.list();
    });
  }

  void _start() =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DraughtsGamePage(
            session: DraughtsSession(DraughtsRules.forVariant(_selected)),
          ),
        ),
      ).then((_) {
        _reloadRecords();
      });

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
    _reloadRecords();
  }

  void _open(DraughtsRecord record) {
    late final DraughtsSession session;
    try {
      session = record.sessionState == null
          ? DraughtsSession(DraughtsRules.forVariant(record.variant))
          : DraughtsSession.fromJson(record.sessionState);
      if (session.variant != record.variant) {
        throw const FormatException('record variant does not match session');
      }
      if (record.sessionState == null) {
        for (final move in record.moves) {
          if (!session.applyMove(move)) {
            throw const FormatException('record contains an illegal move');
          }
        }
        if (!session.gameOver) {
          switch (record.result) {
            case '1/2-1/2':
              session.agreeDraw();
            case '1-0':
              session.resign(Side.white);
            case '0-1':
              session.resign(Side.black);
          }
        }
      }
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法恢复对局：$error')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DraughtsGamePage(
          session: session,
          recordId: record.id,
          savedAt: record.createdAt,
          aiLevel: record.kind == DraughtsGameKind.ai
              ? record.aiLevel ?? DraughtsAiLevel.intermediate
              : null,
          humanSide: record.localSide ?? Side.white,
        ),
      ),
    ).then((_) {
      _reloadRecords();
    });
  }

  Future<void> _importPdn() async {
    final controller = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入 PDN 棋谱'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              hintText: '粘贴包含 [Variant "..."] 标头的 PDN',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (source == null || source.trim().isEmpty || !mounted) return;
    try {
      final parsed = DraughtsNotation.importPdn(source);
      final imported = DraughtsRecord(
        id: 'pdn-${DateTime.now().microsecondsSinceEpoch}',
        variant: parsed.variant,
        moves: parsed.moves,
        kind: parsed.kind,
        localSide: parsed.localSide,
        createdAt: parsed.createdAt,
        result: parsed.result,
      );
      await DraughtsStorage.save(imported);
      if (!mounted) return;
      _open(imported);
      _reloadRecords();
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
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
          onPressed: _importPdn,
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('导入 PDN 棋谱'),
        ),
        const SizedBox(height: 24),
        Text(
          '最近对局',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        FutureBuilder<List<DraughtsRecord>>(
          future: _records,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            final records = snapshot.data ?? const [];
            if (records.isEmpty) {
              return const ListTile(title: Text('还没有保存的跳棋对局'));
            }
            return Column(
              children: [
                for (final record in records.take(20))
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(record.variant.label),
                      subtitle: Text(
                        '${switch (record.kind) {
                          DraughtsGameKind.local => '本地',
                          DraughtsGameKind.online => '联机',
                          DraughtsGameKind.ai => '人机 · ${record.aiLevel?.label ?? '中级'}',
                        }} · ${record.moves.length} 手 · ${record.createdAt.toLocal()}',
                      ),
                      trailing: IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (record.id != null) {
                            await DraughtsStorage.delete(record.id!);
                          }
                          _reloadRecords();
                        },
                      ),
                      onTap: () => _open(record),
                    ),
                  ),
              ],
            );
          },
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
