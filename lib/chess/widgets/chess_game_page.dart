import 'dart:async';
import 'dart:convert';

import '../../records/board_record.dart';
import '../../records/board_record_storage.dart';
import '../../records/record_replay.dart';
import '../../records/widgets/record_playback_page.dart';
import 'package:flutter/material.dart';
import '../chess.dart';
import '../chess_match_controller.dart';
import '../engine/chess_engine.dart';
import '../engine/stockfish_runtime.dart';
import '../../lan/chess_lan_game.dart';
import '../../lan/lan_protocol.dart';
import '../../lan/lan_rematch_card.dart';
import '../../lan/lan_transport.dart';
import 'chess_board.dart';

enum ChessGameMode { local, ai, online }

class ChessGamePage extends StatefulWidget {
  const ChessGamePage({
    super.key,
    this.initialSession,
    this.recordId,
    this.createdAt,
  }) : mode = ChessGameMode.local,
       humanSide = Side.white,
       level = ChessAiLevel.normal,
       connection = null,
       engine = null;
  const ChessGamePage.ai({
    super.key,
    required this.humanSide,
    required this.level,
    this.engine,
    this.initialSession,
    this.recordId,
    this.createdAt,
  }) : mode = ChessGameMode.ai,
       connection = null;
  const ChessGamePage.online({super.key, required this.connection})
    : mode = ChessGameMode.online,
      humanSide = Side.white,
      level = ChessAiLevel.normal,
      engine = null,
      initialSession = null,
      recordId = null,
      createdAt = null;
  final ChessGameMode mode;
  final Side humanSide;
  final ChessAiLevel level;
  final LanClientConnection? connection;
  final ChessEngine? engine;
  final ChessSession? initialSession;
  final String? recordId;
  final DateTime? createdAt;
  @override
  State<ChessGamePage> createState() => _ChessGamePageState();
}

class _ChessGamePageState extends State<ChessGamePage>
    with WidgetsBindingObserver {
  ChessMatchController? _local;
  StreamSubscription<LanMessage>? _messages;
  StreamSubscription<void>? _disconnects;
  Timer? _pendingTimer;
  Cell? _selected;
  bool _flipped = false,
      _disconnected = false,
      _syncing = false,
      _pending = false,
      _choosing = false;
  String? _notice;
  late String _recordId =
      widget.recordId ?? BoardGameRecord.newId(BoardRecordGame.chess);
  late DateTime _createdAt = widget.createdAt ?? DateTime.now().toUtc();
  late bool _hasRecord = widget.recordId != null;
  String? _lastSnapshot, _saveError;
  int _round = 0;
  bool _active = true, _browsing = false, _restarting = false, _closing = false;

  bool get _online => widget.mode == ChessGameMode.online;
  ChessLanReplica get _replica => widget.connection!.chessReplica!;
  ChessSession get _session => _online ? _replica.session : _local!.session;
  Side get _side => _online ? widget.connection!.side! : widget.humanSide;
  bool get _negotiating =>
      _online && (_replica.undoRequest != null || _replica.drawRequest != null);
  bool get _connected => !_disconnected && !_syncing && !_pending;
  bool get _canPlay =>
      !_choosing &&
      _active &&
      !_browsing &&
      !_restarting &&
      (_online
          ? _connected &&
                widget.connection!.started &&
                !_negotiating &&
                !_session.gameOver &&
                _session.turn == _side
          : _local!.canPlay);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flipped = widget.mode == ChessGameMode.ai && _side == Side.black;
    if (_online) {
      _round = _replica.round;
      _messages = widget.connection!.messages.listen(_onMessage);
      _disconnects = widget.connection!.disconnections.listen((_) {
        if (mounted) {
          setState(() {
            _disconnected = true;
            _pending = false;
            _selected = null;
          });
        }
      });
    } else {
      _local = ChessMatchController(
        session: widget.initialSession,
        engine: widget.mode == ChessGameMode.ai
            ? widget.engine ?? createChessEngine()
            : null,
        humanSide: widget.humanSide,
        level: widget.level,
      )..addListener(_refresh);
    }
    if (widget.recordId != null) _lastSnapshot = jsonEncode(_session.toJson());
    unawaited(_persist());
    if (!_online) unawaited(_local!.runAi());
  }

  void _refresh() {
    if (mounted && !_closing) setState(() {});
    if (!_closing && !_restarting) unawaited(_persist());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _active = state == AppLifecycleState.resumed);
    if (_active) {
      if (!_browsing &&
          !_restarting &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        unawaited(_local?.resume());
      }
    } else {
      unawaited(_local?.suspend());
      unawaited(_persist());
    }
  }

  void _newRecord() {
    _recordId = BoardGameRecord.newId(BoardRecordGame.chess);
    _createdAt = DateTime.now().toUtc();
    _hasRecord = false;
    _lastSnapshot = null;
  }

  BoardGameRecord _snapshot() => BoardGameRecord.fromChess(
    _session,
    id: _recordId,
    createdAt: _createdAt,
    kind: _online
        ? BoardRecordKind.online
        : widget.mode == ChessGameMode.ai
        ? BoardRecordKind.ai
        : BoardRecordKind.local,
    humanSide: _side,
    aiLevel: widget.level,
  );

  Future<bool> _persist({bool force = false}) async {
    if (_restarting && !force) return true;
    if (_session.moves.isEmpty && !_session.gameOver && !_hasRecord) {
      return true;
    }
    final snapshot = jsonEncode(_session.toJson());
    if (!force && snapshot == _lastSnapshot) return true;
    final record =
        _snapshot(); // Capture before any await or controller disposal.
    _lastSnapshot = snapshot;
    _hasRecord = true;
    try {
      await BoardRecordStorage.save(record);
      if (mounted && !_closing && _saveError != null) {
        setState(() => _saveError = null);
      }
      return true;
    } catch (_) {
      if (_lastSnapshot == snapshot) _lastSnapshot = null;
      if (mounted && !_closing) setState(() => _saveError = '棋谱保存失败，请重试');
      return false;
    }
  }

  Future<void> _playRecord() async {
    if (_browsing || _restarting || _choosing) return;
    setState(() {
      _browsing = true;
      _selected = null;
    });
    try {
      await _local?.suspend();
      if (!mounted) return;
      final replay = ChessRecordReplay(_snapshot());
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => RecordPlaybackPage(record: replay)),
      );
    } catch (error) {
      if (mounted) setState(() => _notice = '无法播放棋谱：$error');
    } finally {
      if (mounted) {
        setState(() => _browsing = false);
        if (_active && (ModalRoute.of(context)?.isCurrent ?? false)) {
          unawaited(_local?.resume());
        }
      }
    }
  }

  Future<void> _restart() async {
    if (_restarting ||
        _browsing ||
        !await _confirm('重新开局', '结束当前对局并重新开始？') ||
        !mounted) {
      return;
    }
    setState(() {
      _restarting = true;
      _selected = null;
    });
    try {
      await _local!.suspend();
      if (!mounted || !await _persist(force: true)) return;
      final before = _session;
      await _local!.restart();
      if (!identical(before, _session)) _newRecord();
    } finally {
      if (mounted) {
        setState(() => _restarting = false);
        if (_active && (ModalRoute.of(context)?.isCurrent ?? false)) {
          unawaited(_local!.resume());
        }
        unawaited(_persist());
      }
    }
  }

  Future<void> _onCell(Cell cell) async {
    if (!_canPlay) return;
    final session = _session;
    final candidates = _selected == null
        ? <ChessMove>[]
        : session
              .legalMovesFrom(_selected!)
              .where((m) => m.to == cell)
              .toList();
    if (candidates.isEmpty) {
      setState(
        () => _selected = session.position.pieceAt(cell)?.side == session.turn
            ? cell
            : null,
      );
      return;
    }
    final fen = session.fen;
    setState(() => _choosing = true);
    final move = await chooseChessPromotion(context, candidates, session.turn);
    if (!mounted) return;
    setState(() => _choosing = false);
    if (move == null ||
        !identical(session, _session) ||
        fen != _session.fen ||
        !_canPlay) {
      return;
    }
    setState(() => _selected = null);
    if (_online) {
      _send(LanMessageType.move, {'move': moveToUci(move)});
    } else {
      _local!.play(move);
    }
  }

  void _send(LanMessageType type, [Map<String, Object?> body = const {}]) {
    if (!_connected) return;
    try {
      widget.connection!.send(
        LanMessage(type, _replica.seq + 1, {
          ...body,
          'side': LanMessage.sideCode(_side),
        }),
      );
      setState(() {
        _pending = true;
        _notice = '等待主机确认…';
        _selected = null;
      });
      _pendingTimer?.cancel();
      _pendingTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || !_pending) return;
        try {
          widget.connection!.send(_replica.stateRequest());
        } catch (_) {
          setState(() {
            _disconnected = true;
            _pending = false;
          });
        }
      });
    } catch (error) {
      setState(() {
        _notice = '发送失败：$error';
        _disconnected = true;
      });
    }
  }

  void _onMessage(LanMessage message) {
    if (!mounted) return;
    if (message.type == LanMessageType.rejected ||
        message.type == LanMessageType.stateSync ||
        LanMessage.eventTypes.contains(message.type)) {
      if (_replica.round != _round) {
        _round = _replica.round;
        _newRecord();
      }
      _pendingTimer?.cancel();
      setState(() {
        _pending = false;
        _selected = null;
        _notice = message.type == LanMessageType.rejected
            ? message.body['reason'] as String?
            : null;
      });
      if (message.type != LanMessageType.rejected) unawaited(_persist());
      if (message.type == LanMessageType.rejected) {
        try {
          widget.connection!.send(_replica.stateRequest());
        } catch (_) {
          setState(() => _disconnected = true);
        }
      }
    }
  }

  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _resign() async {
    if (!await _confirm(
          '认输',
          '${widget.mode == ChessGameMode.local ? _session.turn.label : _side.label}确认认输吗？',
        ) ||
        !mounted) {
      return;
    }
    if (_online) {
      _send(LanMessageType.resign);
    } else {
      await _local!.resign();
    }
  }

  Future<void> _draw() async {
    if (_online) {
      _send(LanMessageType.drawRequest);
      return;
    }
    if (await _confirm('和棋协商', '${_session.turn.opponent.label}是否同意和棋？') &&
        mounted) {
      await _local!.agreeDraw();
    }
  }

  Future<void> _claim() async {
    ChessMove? intended;
    if (_session.claimableDraw() == null) {
      final eligible = _session
          .legalMoves()
          .where((m) => _session.claimableDraw(m) != null)
          .toList();
      if (eligible.isEmpty) return;
      intended = await showDialog<ChessMove>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('声明下一步并申请和棋'),
          children: [
            for (final move in eligible)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, move),
                child: Text(moveToUci(move)),
              ),
          ],
        ),
      );
      if (!mounted || intended == null) return;
    }
    if (_online) {
      _send(LanMessageType.drawClaim, {
        if (intended != null) 'move': moveToUci(intended),
      });
    } else {
      await _local!.claimDraw(intended);
    }
  }

  Future<void> _reconnect() async {
    setState(() {
      _syncing = true;
      _notice = '重连中…';
    });
    try {
      await widget.connection!.reconnect();
      if (mounted) {
        setState(() {
          _disconnected = false;
          _pending = false;
          _notice = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _notice = '重连失败：$error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String get _status {
    if (_syncing) return '重连中…';
    if (_disconnected) return '与房间失去连接';
    if (_local?.thinking == true) return 'AI 思考中…';
    final result = _session.result;
    if (result != null &&
        widget.mode != ChessGameMode.local &&
        result.winner != null) {
      return '${result.winner == _side ? '你获胜' : '你输了'} · ${result.reason == ChessEndReason.resignation ? (result.winner == _side ? '对方认输' : '你已认输') : '将死'}';
    }
    return _session.status;
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final request = _online
        ? _replica.undoRequest ?? _replica.drawRequest
        : null;
    final drawRequest = _online && _replica.drawRequest != null;
    final enabled =
        !session.gameOver && (!_online || _connected && !_negotiating);
    final canClaim =
        _canPlay &&
        (session.claimableDraw() != null ||
            session.legalMoves().any((m) => session.claimableDraw(m) != null));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '国际象棋 · ${switch (widget.mode) {
            ChessGameMode.local => '本地双人',
            ChessGameMode.ai => 'Stockfish 19',
            ChessGameMode.online => '联机',
          }}',
        ),
        actions: [
          IconButton(
            tooltip: '播放棋谱',
            onPressed: _browsing || _restarting || _choosing
                ? null
                : _playRecord,
            icon: const Icon(Icons.play_circle_outline),
          ),
          if (!_online)
            IconButton(
              tooltip: '翻转棋盘',
              onPressed: () => setState(() => _flipped = !_flipped),
              icon: const Icon(Icons.flip_camera_android),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _status,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            if (widget.mode != ChessGameMode.local)
              Text(
                '你执${_side.label} ${widget.mode == ChessGameMode.ai ? '· ${widget.level.displayLabel}' : ''}',
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),
            ChessBoard(
              session: session,
              onCell: _canPlay ? _onCell : null,
              selected: _selected,
              targets: _selected == null
                  ? const []
                  : session
                        .legalMovesFrom(_selected!)
                        .map((m) => m.to)
                        .toList(),
              flipped: _online ? _side == Side.black : _flipped,
            ),
            const SizedBox(height: 16),
            if (_disconnected)
              Center(
                child: FilledButton(
                  onPressed: _syncing ? null : _reconnect,
                  child: Text(_syncing ? '重连中…' : '重新连接'),
                ),
              ),
            if (request != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        request.side == _side
                            ? '等待对方回应${drawRequest ? '和棋' : '悔棋'}请求'
                            : '对方请求${drawRequest ? '和棋' : '悔棋'}',
                      ),
                      if (request.side != _side)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: !_connected
                                  ? null
                                  : () => _send(
                                      drawRequest
                                          ? LanMessageType.drawReject
                                          : LanMessageType.undoReject,
                                      {
                                        'requestSeq': request.seq,
                                        'reason': '对方拒绝悔棋',
                                      },
                                    ),
                              child: const Text('拒绝'),
                            ),
                            FilledButton(
                              onPressed: !_connected
                                  ? null
                                  : () => _send(
                                      drawRequest
                                          ? LanMessageType.drawAccept
                                          : LanMessageType.undoAccept,
                                      {'requestSeq': request.seq},
                                    ),
                              child: const Text('同意'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (_notice != null || _local?.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _notice ?? _local!.error!,
                  textAlign: TextAlign.center,
                ),
              ),
            if (_saveError != null)
              Center(
                child: TextButton.icon(
                  onPressed: () => _persist(force: true),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saveError!),
                ),
              ),
            if (_local?.error != null)
              Center(
                child: TextButton(
                  onPressed: _local!.runAi,
                  child: const Text('重试 AI'),
                ),
              ),
            if (_online && session.gameOver)
              LanRematchCard(
                request: _replica.rematchRequest,
                side: _side,
                enabled: _connected && widget.connection!.started,
                onSend: _send,
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      (_online
                          ? enabled && _replica.canRequestUndo(_side)
                          : session.canUndo)
                      ? () {
                          setState(() => _selected = null);
                          if (_online) {
                            _send(LanMessageType.undoRequest);
                          } else {
                            unawaited(_local!.undo());
                          }
                        }
                      : null,
                  icon: const Icon(Icons.undo),
                  label: const Text('悔棋'),
                ),
                if (widget.mode != ChessGameMode.ai)
                  OutlinedButton(
                    onPressed: enabled ? _draw : null,
                    child: const Text('和棋协商'),
                  ),
                OutlinedButton(
                  onPressed: enabled ? _resign : null,
                  child: const Text('认输'),
                ),
                if (canClaim)
                  FilledButton.tonal(
                    onPressed: _claim,
                    child: const Text('申请和棋'),
                  ),
                if (!_online)
                  TextButton(
                    onPressed: _restarting || _browsing ? null : _restart,
                    child: const Text('重新开局'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _closing = true;
    unawaited(_persist());
    WidgetsBinding.instance.removeObserver(this);
    _pendingTimer?.cancel();
    _messages?.cancel();
    _disconnects?.cancel();
    _local?.dispose();
    super.dispose();
  }
}
