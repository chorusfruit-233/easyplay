import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../chess/widgets/chess_game_page.dart';
import '../../record_file_service.dart';
import '../../xiangqi/widgets/xiangqi_game_page.dart';
import '../board_record.dart';
import '../board_record_notation.dart';
import '../board_record_storage.dart';
import '../record_replay.dart';
import 'record_playback_page.dart';
import 'record_copy.dart';

enum _Action { copyNotation, copyJson, notation, json, delete }

class BoardLibraryPage extends StatefulWidget {
  const BoardLibraryPage({super.key, required this.game});
  final BoardRecordGame game;
  @override
  State<BoardLibraryPage> createState() => _BoardLibraryPageState();
}

class _BoardLibraryPageState extends State<BoardLibraryPage> {
  List<BoardGameRecord> _records = [];
  bool _loading = true, _failed = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final records = await BoardRecordStorage.list(widget.game);
      if (mounted) setState(() => _records = records);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _play(BoardGameRecord record) async {
    try {
      final replay = record.game == BoardRecordGame.chess
          ? ChessRecordReplay(record)
          : XiangqiRecordReplay(record);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => RecordPlaybackPage(record: replay)),
      );
    } catch (error) {
      _notice('无法播放棋谱：$error');
    }
  }

  Future<void> _open(BoardGameRecord record) async {
    if (record.gameOver || record.kind == BoardRecordKind.online) {
      return _play(record);
    }
    try {
      final Widget page;
      if (record.game == BoardRecordGame.chess) {
        final session = record.restoreChess();
        page = record.kind == BoardRecordKind.ai
            ? ChessGamePage.ai(
                initialSession: session,
                recordId: record.id,
                createdAt: record.createdAt,
                humanSide: record.chessSide,
                level: record.chessLevel,
              )
            : ChessGamePage(
                initialSession: session,
                recordId: record.id,
                createdAt: record.createdAt,
              );
      } else {
        final session = record.restoreXiangqi();
        page = record.kind == BoardRecordKind.ai
            ? XiangqiGamePage.ai(
                initialSession: session,
                recordId: record.id,
                createdAt: record.createdAt,
                humanSide: record.xiangqiSide,
                level: record.xiangqiLevel,
              )
            : XiangqiGamePage(
                initialSession: session,
                recordId: record.id,
                createdAt: record.createdAt,
              );
      }
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
      if (mounted) await _load();
    } catch (error) {
      _notice('无法恢复棋谱：$error');
    }
  }

  Future<void> _copy(BoardGameRecord record, {required bool json}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final chess = record.game == BoardRecordGame.chess;
      await copyRecordText(
        context,
        text: json
            ? BoardRecordNotation.toJson(record)
            : chess
            ? BoardRecordNotation.toPgn(record)
            : BoardRecordNotation.toIccs(record),
        label: json
            ? 'JSON 完整备份'
            : chess
            ? 'PGN 棋谱'
            : 'ICCS 着法',
      );
    } catch (error) {
      _notice('复制失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(BoardGameRecord record, {required bool json}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final chess = record.game == BoardRecordGame.chess;
      final saved = await RecordFileService.saveText(
        json
            ? BoardRecordNotation.toJson(record)
            : chess
            ? BoardRecordNotation.toPgn(record)
            : BoardRecordNotation.toIccs(record),
        fileName: BoardRecordNotation.fileName(
          record,
          json
              ? 'json'
              : chess
              ? 'pgn'
              : 'txt',
        ),
        mimeType: json
            ? 'application/json;charset=utf-8'
            : chess
            ? 'application/x-chess-pgn;charset=utf-8'
            : 'text/plain;charset=utf-8',
      );
      if (saved) _notice(json ? 'JSON 完整备份已导出' : '棋谱已导出');
    } catch (error) {
      _notice('导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null || !mounted) return;
      final file = picked.files.single;
      if (file.size > 5 * 1024 * 1024) {
        throw const FormatException('棋谱文件超过 5 MB');
      }
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('无法读取棋谱文件内容');
      final record = BoardRecordNotation.importJson(
        utf8.decode(bytes),
        widget.game,
      );
      await BoardRecordStorage.save(record);
      if (mounted) await _load();
      _notice('棋谱已导入');
    } catch (error) {
      _notice('导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BoardGameRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除棋谱？'),
        content: Text(
          '${record.game.label} · ${record.moveCount} 手\n删除后无法恢复，建议先导出备份。',
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
      await BoardRecordStorage.delete(widget.game, record.id);
      await _load();
      _notice('棋谱已删除');
    } catch (error) {
      _notice('删除失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.game.label}棋谱库'),
      actions: [
        IconButton(
          tooltip: '导入 JSON 完整备份',
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.file_open_outlined),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _failed
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
                  Text(
                    '对局会自动保存到这里。未完成的本地、人机对局可继续，所有棋谱均可播放、复制或导出。',
                    textAlign: TextAlign.center,
                  ),
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
                      '${widget.game == BoardRecordGame.chess ? 'PGN 用于交流着法' : 'ICCS 文本记录坐标着法'}；JSON 用于完整备份和导入。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }
                final record = _records[index - 1];
                final state = record.gameOver
                    ? record.resultLabel
                    : record.kind == BoardRecordKind.online
                    ? '回看棋谱'
                    : '继续对局';
                return ListTile(
                  key: ValueKey('${widget.game.name}-record-${record.id}'),
                  leading: const Icon(Icons.collections_bookmark_outlined),
                  title: Text('${record.game.label} · ${record.moveCount} 手'),
                  subtitle: Text(
                    '${record.modeLabel} · $state\n${record.createdAt.toLocal().toString().split('.').first}',
                  ),
                  isThreeLine: true,
                  onTap: _busy ? null : () => _open(record),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '播放棋谱',
                        onPressed: _busy ? null : () => _play(record),
                        icon: const Icon(Icons.play_circle_outline),
                      ),
                      PopupMenuButton<_Action>(
                        tooltip: '棋谱操作',
                        enabled: !_busy,
                        onSelected: (action) => switch (action) {
                          _Action.copyNotation => _copy(record, json: false),
                          _Action.copyJson => _copy(record, json: true),
                          _Action.notation => _export(record, json: false),
                          _Action.json => _export(record, json: true),
                          _Action.delete => _delete(record),
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: _Action.copyNotation,
                            child: Text(
                              widget.game == BoardRecordGame.chess
                                  ? '复制 PGN'
                                  : '复制 ICCS 着法',
                            ),
                          ),
                          const PopupMenuItem(
                            value: _Action.copyJson,
                            child: Text('复制 JSON 完整备份'),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: _Action.notation,
                            child: Text(
                              widget.game == BoardRecordGame.chess
                                  ? '导出 PGN'
                                  : '导出 ICCS 着法',
                            ),
                          ),
                          const PopupMenuItem(
                            value: _Action.json,
                            child: Text('导出 JSON 完整备份'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: _Action.delete,
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
