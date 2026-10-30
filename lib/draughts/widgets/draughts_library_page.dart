import 'package:flutter/material.dart';

import '../../game_session.dart' show Side;
import '../../record_file_service.dart';
import '../../records/record_replay.dart';
import '../../records/widgets/record_playback_page.dart';
import '../../records/widgets/record_copy.dart';
import '../draughts_ai_level.dart';
import '../draughts_notation.dart';
import '../draughts_record.dart';
import '../draughts_storage.dart';
import '../draughts_variant.dart';
import 'draughts_ai_duel_page.dart';
import 'draughts_game_page.dart';

/// All saved draughts games, with portable PDN export and import.
class DraughtsLibraryPage extends StatefulWidget {
  const DraughtsLibraryPage({super.key});

  @override
  State<DraughtsLibraryPage> createState() => _DraughtsLibraryPageState();
}

class _DraughtsLibraryPageState extends State<DraughtsLibraryPage> {
  late Future<List<DraughtsRecord>> _records = DraughtsStorage.list();
  final _sharing = <DraughtsRecord>{};

  Future<void> _reload() async {
    final next = DraughtsStorage.list();
    setState(() {
      _records = next;
    });
    // FutureBuilder presents failures with a retry action.
    try {
      await next;
    } catch (_) {}
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(DraughtsRecord record) async {
    try {
      final session = record.restore();
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => record.kind == DraughtsGameKind.aiDuel
              ? DraughtsAiDuelPage(
                  session: session,
                  config: record.aiDuel!,
                  recordId: record.id,
                  createdAt: record.createdAt,
                  initiallyPaused: true,
                )
              : DraughtsGamePage(
                  session: session,
                  recordId: record.id,
                  savedAt: record.createdAt,
                  aiLevel: record.kind == DraughtsGameKind.ai
                      ? record.aiLevel ?? DraughtsAiLevel.intermediate
                      : null,
                  humanSide: record.localSide ?? Side.white,
                ),
        ),
      );
      if (mounted) await _reload();
    } catch (error) {
      _notice('无法恢复对局：$error');
    }
  }

  Future<void> _copy(DraughtsRecord record) async {
    if (_sharing.contains(record)) return;
    setState(() => _sharing.add(record));
    try {
      await copyRecordText(
        context,
        text: DraughtsNotation.exportPdn(record),
        label: 'PDN 棋谱',
      );
    } catch (error) {
      _notice('复制失败：$error');
    } finally {
      if (mounted) setState(() => _sharing.remove(record));
    }
  }

  Future<void> _export(DraughtsRecord record) async {
    if (_sharing.contains(record)) return;
    setState(() => _sharing.add(record));
    try {
      final saved = await RecordFileService.saveText(
        DraughtsNotation.exportPdn(record),
        fileName: DraughtsNotation.fileName(record),
        mimeType: 'application/x-chess-pdn;charset=utf-8',
      );
      _notice(saved ? '棋谱已导出' : '已取消导出');
    } catch (error) {
      _notice('导出失败：$error');
    } finally {
      if (mounted) setState(() => _sharing.remove(record));
    }
  }

  Future<void> _play(DraughtsRecord record) async {
    try {
      final replay = DraughtsRecordReplay(record);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => RecordPlaybackPage(record: replay)),
      );
    } catch (error) {
      _notice('无法播放棋谱：$error');
    }
  }

  Future<void> _delete(DraughtsRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除棋谱？'),
        content: Text(
          '${record.variant.label} · ${record.moves.length} 手\n删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await DraughtsStorage.delete(record.id!);
      if (mounted) await _reload();
      _notice('棋谱已删除');
    } catch (error) {
      _notice('删除失败：$error');
    }
  }

  Future<void> _importPdn() async {
    var draft = '';
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入 PDN 棋谱'),
        scrollable: true,
        content: SizedBox(
          width: 560,
          child: TextField(
            onChanged: (value) => draft = value,
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
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('导入'),
          ),
        ],
      ),
    );
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
      await _reload();
      _notice('棋谱已导入');
    } catch (error) {
      _notice('导入失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('棋谱库'),
      actions: [
        IconButton(
          tooltip: '导入 PDN 棋谱',
          onPressed: _importPdn,
          icon: const Icon(Icons.file_open_outlined),
        ),
      ],
    ),
    body: FutureBuilder<List<DraughtsRecord>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _message(
            icon: Icons.error_outline,
            title: '棋谱加载失败',
            detail: '${snapshot.error}',
            action: FilledButton.tonalIcon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          );
        }
        final records = snapshot.data ?? const <DraughtsRecord>[];
        if (records.isEmpty) {
          return _message(
            icon: Icons.collections_bookmark_outlined,
            title: '还没有棋谱',
            detail: '跳棋对局会自动保存在这里，也可以导入 PDN 棋谱。',
            action: FilledButton.tonalIcon(
              onPressed: _importPdn,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('导入 PDN 棋谱'),
            ),
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: RefreshIndicator(
              onRefresh: _reload,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: records.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _row(records[index]),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _message({
    required IconData icon,
    required String title,
    required String detail,
    required Widget action,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          action,
        ],
      ),
    ),
  );

  Widget _row(DraughtsRecord record) => ListTile(
    key: ValueKey('draughts-record-${record.id}'),
    title: Text(record.variant.label),
    subtitle: Text(
      '${switch (record.kind) {
        DraughtsGameKind.local => '本地',
        DraughtsGameKind.online => '联机',
        DraughtsGameKind.ai => '人机 · ${record.aiLevel?.label ?? '中级'}',
        DraughtsGameKind.aiDuel => 'AI 对抗 · 黑${record.aiDuel!.blackLevel.label} / 白${record.aiDuel!.whiteLevel.label}',
      }} · ${record.moves.length} 手 · ${switch (record.result) {
        '1-0' => '黑方胜',
        '0-1' => '白方胜',
        '1/2-1/2' => '和棋',
        _ => '进行中',
      }}\n${record.createdAt.toLocal()}',
    ),
    isThreeLine: true,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          tooltip: '播放棋谱',
          onPressed: () => _play(record),
          icon: const Icon(Icons.play_circle_outline),
        ),
        SizedBox.square(
          dimension: 48,
          child: PopupMenuButton<String>(
            tooltip: '棋谱操作',
            onSelected: (action) => switch (action) {
              'copy' => _copy(record),
              'export' => _export(record),
              _ => _delete(record),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'copy',
                enabled: !_sharing.contains(record),
                child: const Text('复制 PDN'),
              ),
              PopupMenuItem(
                value: 'export',
                enabled: !_sharing.contains(record),
                child: const Text('导出 PDN'),
              ),
              PopupMenuItem(
                value: 'delete',
                enabled: record.id != null,
                child: const Text('删除棋谱'),
              ),
            ],
          ),
        ),
      ],
    ),
    onTap: () => _open(record),
  );
}
