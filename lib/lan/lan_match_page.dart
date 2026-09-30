import 'dart:async';

import 'package:flutter/material.dart';

import '../board.dart';
import '../game_session.dart';
import '../go_placement.dart';
import '../go_storage.dart';
import 'lan_protocol.dart';
import 'lan_rematch_card.dart';
import 'lan_transport.dart';

/// A LAN game has one source of truth: committed events from the host.
/// The board never applies a local move speculatively, and no engine is owned
/// or started by this screen.
class LanMatchPage extends StatefulWidget {
  const LanMatchPage({super.key, required this.connection});

  final LanClientConnection connection;

  @override
  State<LanMatchPage> createState() => _LanMatchPageState();
}

class _LanMatchPageState extends State<LanMatchPage> {
  StreamSubscription<LanMessage>? _subscription;
  StreamSubscription<void>? _disconnects;
  Timer? _retry;
  late final String _gameId = DateTime.now().microsecondsSinceEpoch.toString();
  final Set<Cell> _dead = {};
  bool _pending = false;
  bool _recovering = false;
  GoPlacementMode _placementMode = GoPlacementMode.automatic;
  int? _shownUndo;
  int? _shownScore;
  int _round = 1;
  String? _status;

  LanClientConnection get _connection => widget.connection;
  GameSession get _session => _connection.replica!.session;
  Side get _side => _connection.side!;
  bool get _myTurn =>
      !_recovering &&
      !_pending &&
      !_session.gameOver &&
      _session.turn == _side &&
      _connection.replica!.undoRequest == null;

  @override
  void initState() {
    super.initState();
    _subscription = _connection.messages.listen(_onMessage);
    _disconnects = _connection.disconnections.listen((_) => _onDisconnected());
    GoPlacementPreferences.load().then((mode) {
      if (mounted) setState(() => _placementMode = mode);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _disconnects?.cancel();
    _retry?.cancel();
    _connection.close();
    super.dispose();
  }

  void _onMessage(LanMessage message) {
    if (!mounted) return;
    if (_round != _connection.replica!.round) {
      _round = _connection.replica!.round;
      _dead.clear();
      _status = null;
    }
    if (LanMessage.eventTypes.contains(message.type)) {
      if (message.type == LanMessageType.scoreAccept) _dead.clear();
      if (_connection.replica!.seq < message.seq) {
        _connection.send(_connection.replica!.stateRequest());
      }
      _pending = false;
      _persist();
    } else if (message.type == LanMessageType.stateSync) {
      _pending = false;
      _recovering = false;
      _status = null;
      _persist();
    } else if (message.type == LanMessageType.rejected) {
      _pending = false;
      _status = message.body['reason'] as String?;
    }
    setState(() {});
    final undo = _connection.replica!.undoRequest;
    if (undo != null && undo.side != _side && _shownUndo != undo.seq) {
      _shownUndo = undo.seq;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _answerUndo(undo.seq),
      );
    }
    final score = _connection.replica!.scoreProposal;
    if (score != null && score.side != _side && _shownScore != score.seq) {
      _shownScore = score.seq;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _answerScore(score.seq),
      );
    }
  }

  void _onDisconnected() {
    if (!mounted) return;
    setState(() {
      _recovering = true;
      _pending = false;
      _status = '失去联系，正在等待重连。棋谱已保留。';
    });
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), () async {
      if (!mounted || !_recovering) return;
      try {
        await _connection.reconnect();
        if (mounted) _connection.send(_connection.replica!.stateRequest());
      } catch (_) {
        if (mounted) _scheduleReconnect();
      }
    });
  }

  Future<void> _persist() async {
    try {
      await GoStorage.saveLast(
        _connection.replica!.sgf,
        gameId: '$_gameId-${_connection.replica!.round}',
        kind: GoGameKind.online,
        humanSide: _side,
      );
    } catch (error) {
      if (mounted) setState(() => _status = '保存棋谱失败：$error');
    }
  }

  void _submit(LanMessageType type, [Map<String, Object?> body = const {}]) {
    if (_pending || _recovering) return;
    final seq = _connection.replica!.seq + 1;
    _pending = true;
    setState(() {});
    try {
      _connection.send(
        LanMessage(type, seq, {'side': LanMessage.sideCode(_side), ...body}),
      );
    } catch (_) {
      _onDisconnected();
    }
  }

  Future<void> _answerUndo(int seq) async {
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('对手请求悔棋'),
        content: const Text('同意后撤回最后一手。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意'),
          ),
        ],
      ),
    );
    if (!mounted || _connection.replica!.undoRequest?.seq != seq) return;
    _submit(
      accept == true ? LanMessageType.undoAccept : LanMessageType.undoReject,
      {'requestSeq': seq, if (accept != true) 'reason': '对手拒绝悔棋'},
    );
  }

  Future<void> _answerScore(int seq) async {
    if (!mounted) return;
    final proposal = _connection.replica!.scoreProposal;
    if (proposal == null || proposal.seq != seq) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('对手提交计分'),
        content: Text('对手标记了 ${proposal.deadStones.length} 颗死子。是否同意？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('不同意'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意'),
          ),
        ],
      ),
    );
    if (!mounted || _connection.replica!.scoreProposal?.seq != seq) return;
    if (accept == true) {
      _submit(LanMessageType.scoreAccept, {'requestSeq': seq});
    } else {
      _submit(LanMessageType.scoreCounter, {
        'requestSeq': seq,
        'deadStones': _dead.map((cell) => [cell.row, cell.col]).toList(),
      });
    }
  }

  void _onCell(Cell cell) {
    if (_session.gameOver) {
      if (_session.goScoreConfirmed ||
          _session.goResignedSide != null ||
          _session.pieceAt(cell) == null) {
        return;
      }
      setState(() {
        if (!_dead.add(cell)) _dead.remove(cell);
      });
      return;
    }
    if (!_myTurn || !_session.isLegalGoMove(cell)) return;
    _submit(LanMessageType.move, {
      'cell': [cell.row, cell.col],
    });
  }

  void _previewCell(Cell cell) {
    if (!_myTurn || !_session.isLegalGoMove(cell)) return;
    setState(() {});
  }

  void _cancelPreview() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final game = _session;
    if (!game.goScoreConfirmed) game.deadGoStones.addAll(_dead);
    final score = game.gameOver && game.goScoreConfirmed
        ? game.calculateGoScore()
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('联机对弈')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '你执${_side == Side.black ? '黑' : '白'} · ${game.goConfig.boardSize} 路 · ${game.goConfig.rules.label}',
            ),
            const SizedBox(height: 8),
            Text(
              game.goResignedSide != null
                  ? '终局：${game.goResignedSide!.label}中盘认输'
                  : score != null
                  ? '终局：${score.result}'
                  : game.gameOver
                  ? '双方标记死子后提交计分'
                  : _myTurn
                  ? '轮到你落子'
                  : '等待对手落子',
            ),
            if (_status != null)
              Text(
                _status!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            Board(
              key: ValueKey(_connection.replica!.seq),
              type: GameType.go,
              session: game,
              selected: null,
              targets: const [],
              onCell: _onCell,
              placementMode: _placementMode,
              onPreviewCell: _previewCell,
              onCancelPreview: _cancelPreview,
            ),
            const SizedBox(height: 16),
            if (!game.gameOver)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _myTurn
                        ? () => _submit(LanMessageType.pass)
                        : null,
                    child: const Text('停一手'),
                  ),
                  OutlinedButton(
                    onPressed:
                        !_pending &&
                            !_recovering &&
                            _connection.replica!.canRequestUndo(_side)
                        ? () => _submit(LanMessageType.undoRequest)
                        : null,
                    child: const Text('请求悔棋'),
                  ),
                  TextButton(
                    onPressed: !_pending && !_recovering
                        ? () => _submit(LanMessageType.resign)
                        : null,
                    child: const Text('认输'),
                  ),
                ],
              ),
            if (game.goScoreConfirmed)
              LanRematchCard(
                request: _connection.replica!.rematchRequest,
                side: _side,
                enabled: !_pending && !_recovering,
                onSend: _submit,
              ),
            if (game.gameOver &&
                !game.goScoreConfirmed &&
                game.goResignedSide == null)
              FilledButton(
                onPressed:
                    _pending ||
                        _recovering ||
                        _connection.replica!.scoreProposal != null
                    ? null
                    : () => _submit(LanMessageType.scoreProposal, {
                        'deadStones': _dead
                            .map((cell) => [cell.row, cell.col])
                            .toList(),
                      }),
                child: const Text('提交死子标记'),
              ),
          ],
        ),
      ),
    );
  }
}
