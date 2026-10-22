import 'package:flutter/material.dart';

import '../../record_file_service.dart';
import '../../records/record_replay.dart';
import '../../records/widgets/record_playback_page.dart';
import '../gomoku_notation.dart';
import '../gomoku_storage.dart';
import 'gomoku_ai_duel_page.dart';
import 'gomoku_game_page.dart';

enum _RecordAction { sgf, json, delete }

class GomokuLibraryPage extends StatefulWidget {
  const GomokuLibraryPage({super.key});

  @override
  State<GomokuLibraryPage> createState() => _GomokuLibraryPageState();
}

class _GomokuLibraryPageState extends State<GomokuLibraryPage> {
  List<GomokuRecord> _records = [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final records = await GomokuStorage.list();
      if (mounted) setState(() => _records = records);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(GomokuRecord record) async {
    try {
      final session = record.restore();
      final aiDuel = record.aiDuel;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => record.variant.playableRule && aiDuel != null
              ? GomokuAiDuelPage(
                  session: session,
                  config: aiDuel,
                  recordId: record.id,
                  createdAt: record.createdAt,
                  initiallyPaused: true,
                )
              : GomokuGamePage(
                  session: session,
                  recordId: record.id,
                  createdAt: record.createdAt,
                  aiLevel: record.aiLevel,
                  humanSide: record.humanSide,
                  readOnly: !record.variant.playableRule,
                ),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      _notice('无法恢复棋谱：$error');
    }
  }

  Future<void> _export(GomokuRecord record, {required bool json}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final saved = await RecordFileService.saveText(
        json ? GomokuNotation.toJson(record) : GomokuNotation.toSgf(record),
        fileName: GomokuNotation.fileName(record, json ? 'json' : 'sgf'),
        mimeType: json
            ? 'application/json;charset=utf-8'
            : 'application/x-go-sgf;charset=utf-8',
      );
      if (saved) _notice(json ? 'JSON 完整备份已导出' : 'SGF 棋谱已导出');
    } catch (error) {
      _notice('棋谱导出失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _play(GomokuRecord record) async {
    try {
      final replay = GomokuRecordReplay(record);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => RecordPlaybackPage(record: replay)),
      );
    } catch (error) {
      _notice('无法播放棋谱：$error');
    }
  }

  Future<void> _delete(GomokuRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除棋谱？'),
        content: Text('${_title(record)}\n删除后无法恢复，建议先导出备份。'),
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
      await GomokuStorage.delete(record.id);
      await _load();
      _notice('棋谱已删除');
    } catch (error) {
      _notice('删除失败：$error');
    }
  }

  String _title(GomokuRecord record) =>
      '${record.variant.label} · ${record.moveCount} 手';

  String _summary(GomokuRecord record) {
    final mode = switch (record.aiDuel) {
      final config? =>
        'AI 对抗 · 黑${config.blackLevel.label} / 白${config.whiteLevel.label}',
      null => record.aiLevel == null ? '本地双人' : '人机 · ${record.aiLevel!.label}',
    };
    final state = !record.variant.playableRule
        ? '旧规则 · 仅供查看'
        : record.gameOver
        ? record.resultLabel
        : '继续对局';
    final date = record.createdAt.toLocal().toString().split('.').first;
    return '$mode · $state\n$date';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('棋谱库')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadFailed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('无法读取棋谱库'),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: _load, child: const Text('重试')),
              ],
            ),
          )
        : _records.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.collections_bookmark_outlined, size: 56),
                  SizedBox(height: 16),
                  Text('还没有棋谱'),
                  SizedBox(height: 8),
                  Text('对局会自动保存到这里，之后可继续对局或导出。', textAlign: TextAlign.center),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _records.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      '${_records.length} 份棋谱 · 自动保存，手动删除\n'
                      'SGF 用于交流正式落子与停着；JSON 完整备份保留开局交换、候选点和对局设置。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }
                final record = _records[index - 1];
                return ListTile(
                  key: ValueKey('gomoku-record-${record.id}'),
                  leading: const Icon(Icons.grid_on),
                  title: Text(_title(record)),
                  subtitle: Text(_summary(record)),
                  isThreeLine: true,
                  onTap: _exporting ? null : () => _open(record),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '播放棋谱',
                        onPressed: _exporting ? null : () => _play(record),
                        icon: const Icon(Icons.play_circle_outline),
                      ),
                      PopupMenuButton<_RecordAction>(
                        tooltip: '棋谱操作',
                        enabled: !_exporting,
                        onSelected: (action) => switch (action) {
                          _RecordAction.sgf => _export(record, json: false),
                          _RecordAction.json => _export(record, json: true),
                          _RecordAction.delete => _delete(record),
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _RecordAction.sgf,
                            child: Text('导出 SGF'),
                          ),
                          PopupMenuItem(
                            value: _RecordAction.json,
                            child: Text('导出 JSON 完整备份'),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: _RecordAction.delete,
                            child: Text('删除棋谱'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
  );
}
