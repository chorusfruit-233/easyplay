import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game_session.dart' show Cell, Side, SideX;
import '../draughts_move.dart';
import '../draughts_notation.dart';
import '../draughts_record.dart';
import '../draughts_session.dart';
import '../draughts_storage.dart';
import '../draughts_variant.dart';
import 'draughts_board.dart';

class DraughtsGamePage extends StatefulWidget {
  const DraughtsGamePage({
    super.key,
    required this.session,
    this.recordId,
    this.savedAt,
  });
  final DraughtsSession session;
  final String? recordId;
  final DateTime? savedAt;

  @override
  State<DraughtsGamePage> createState() => _DraughtsGamePageState();
}

class _DraughtsGamePageState extends State<DraughtsGamePage> {
  late final DraughtsSession _session = widget.session;
  Cell? _selected;
  List<Cell> _pendingPath = [];
  List<DraughtsMove> _candidates = [];
  String? _message;
  late final String _recordId =
      widget.recordId ??
      'local-${_session.variant.name}-${DateTime.now().microsecondsSinceEpoch}';
  late final DateTime _createdAt = widget.savedAt ?? DateTime.now().toUtc();

  List<Cell> get _targets {
    if (_selected == null) return const [];
    final prefix = _pendingPath.isEmpty
        ? [_selected!]
        : [_selected!, ..._pendingPath];
    return _candidates
        .where(
          (move) =>
              move.path.length > prefix.length &&
              List.generate(
                prefix.length,
                (i) => move.path[i] == prefix[i],
              ).every((v) => v),
        )
        .map((move) => move.path[prefix.length])
        .toSet()
        .toList();
  }

  void _clearSelection() {
    _selected = null;
    _pendingPath = [];
    _candidates = [];
  }

  void _onCell(Cell cell) {
    if (_session.gameOver) return;
    if (_selected == null) {
      if (_session.pieceAt(cell)?.side != _session.turn) return;
      final candidates = _session.legalMovesFrom(cell);
      if (candidates.isEmpty) return;
      setState(() {
        _selected = cell;
        _pendingPath = [];
        _candidates = candidates;
        _message = candidates.any((m) => m.isCapture) ? '必须吃子；选择完整吃子路径' : null;
      });
      return;
    }
    if (_selected == cell && _pendingPath.isEmpty) {
      setState(_clearSelection);
      return;
    }
    final prefix = [_selected!, ..._pendingPath, cell];
    final matches = _candidates
        .where(
          (move) =>
              move.path.length >= prefix.length &&
              List.generate(
                prefix.length,
                (i) => move.path[i] == prefix[i],
              ).every((v) => v),
        )
        .toList();
    if (matches.isEmpty) {
      if (_session.pieceAt(cell)?.side == _session.turn) {
        final candidates = _session.legalMovesFrom(cell);
        setState(() {
          _selected = candidates.isEmpty ? null : cell;
          _pendingPath = [];
          _candidates = candidates;
          _message = null;
        });
      }
      return;
    }
    final completed = matches
        .where((move) => move.path.length == prefix.length)
        .firstOrNull;
    if (completed != null) {
      if (_session.applyMove(completed)) {
        setState(() {
          _clearSelection();
          _message = null;
        });
        _persist();
      }
      return;
    }
    setState(() {
      _pendingPath = [..._pendingPath, cell];
      _candidates = matches;
      _message = '继续选择下一跳';
    });
  }

  Future<void> _persist() async {
    try {
      await DraughtsStorage.save(
        DraughtsRecord.fromSession(
          _session,
          id: _recordId,
          createdAt: _createdAt,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _message = '自动保存失败：$error');
    }
  }

  Future<void> _undo() async {
    if (!_session.undo()) return;
    setState(() {
      _clearSelection();
      _message = null;
    });
    await _persist();
  }

  Future<void> _resign() async {
    final side = _session.turn;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('认输'),
        content: Text('${side.label}确认认输吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('认输'),
          ),
        ],
      ),
    );
    if (accept == true && _session.resign(side)) {
      setState(() {
        _clearSelection();
        _message = null;
      });
      await _persist();
    }
  }

  Future<void> _draw() async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('和棋'),
        content: const Text('本地双人对局中，双方确认接受和棋吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续对局'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意和棋'),
          ),
        ],
      ),
    );
    if (accept == true && _session.agreeDraw()) {
      setState(() {
        _clearSelection();
        _message = null;
      });
      await _persist();
    }
  }

  Future<void> _showPdn() async {
    final pdn = DraughtsNotation.exportPdn(
      DraughtsRecord.fromSession(
        _session,
        id: _recordId,
        createdAt: _createdAt,
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDN 棋谱'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: SelectableText(pdn)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: pdn));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制'),
          ),
        ],
      ),
    );
  }

  String get _status {
    final result = _session.result;
    if (result != null) {
      if (result.winner == null) {
        return result.reason.name == 'drawRule' ? '按规则和棋' : '双方同意和棋';
      }
      return '${result.winner!.label}获胜 · ${switch (result.reason.name) {
        'resignation' => '认输',
        'noPieces' => '棋子被吃尽',
        'noMoves' => '无合法着法',
        _ => '对局结束',
      }}';
    }
    return '轮到${_session.turn.label}';
  }

  @override
  Widget build(BuildContext context) {
    final pieceCounts = {
      for (final side in Side.values) side: _session.position.count(side),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_session.variant.label),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'pdn') _showPdn();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdn', child: Text('查看 / 导出 PDN')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_session.rules.shortDescription} · ${_session.moveCount} 手',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text('黑方 ${pieceCounts[Side.black]} 子'),
                        Text('白方 ${pieceCounts[Side.white]} 子'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_message!, textAlign: TextAlign.center),
              ),
            DraughtsBoard(
              key: ValueKey(_session.revision),
              session: _session,
              selected: _selected,
              targets: _targets,
              pendingPath: _selected == null
                  ? const []
                  : [_selected!, ..._pendingPath],
              onCell: _onCell,
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _session.moves.isNotEmpty ? _undo : null,
                  icon: const Icon(Icons.undo),
                  label: const Text('悔棋'),
                ),
                OutlinedButton.icon(
                  onPressed: !_session.gameOver ? _draw : null,
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('提和'),
                ),
                TextButton.icon(
                  onPressed: !_session.gameOver ? _resign : null,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('认输'),
                ),
                if (_selected != null)
                  TextButton(
                    onPressed: () => setState(_clearSelection),
                    child: const Text('取消选择'),
                  ),
              ],
            ),
            if (_session.moves.isNotEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('棋谱'),
                  subtitle: Text(
                    _session.moves
                        .asMap()
                        .entries
                        .map(
                          (entry) =>
                              '${entry.key + 1}. ${entry.value.path.map((cell) => '${cell.row + 1},${cell.col + 1}').join(' → ')}',
                        )
                        .join('   '),
                  ),
                  trailing: IconButton(
                    onPressed: _showPdn,
                    icon: const Icon(Icons.share_outlined),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
