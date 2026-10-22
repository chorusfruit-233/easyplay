import 'dart:async';

import 'package:flutter/material.dart';

import '../../game_session.dart' show Cell, Side, SideX;
import '../../go_placement.dart';
import '../../records/record_replay.dart';
import '../../records/widgets/record_playback_page.dart';
import '../gomoku_ai_level.dart';
import '../gomoku_player.dart';
import '../engine/rapfi_player.dart';
import '../gomoku_placement.dart';
import '../gomoku_session.dart';
import '../gomoku_storage.dart';
import 'gomoku_board.dart';
import 'gomoku_opening_panel.dart';

class GomokuGamePage extends StatefulWidget {
  const GomokuGamePage({
    super.key,
    required this.session,
    this.recordId,
    this.createdAt,
    this.aiLevel,
    this.humanSide = Side.black,
    this.ai,
    this.readOnly = false,
  });

  final GomokuSession session;
  final String? recordId;
  final DateTime? createdAt;
  final GomokuAiLevel? aiLevel;
  final Side humanSide;
  final GomokuPlayer? ai;
  final bool readOnly;

  @override
  State<GomokuGamePage> createState() => _GomokuGamePageState();
}

class _GomokuGamePageState extends State<GomokuGamePage>
    with WidgetsBindingObserver {
  late final GomokuSession _session = widget.session;
  late final GomokuPlayer _ai = widget.ai ?? RapfiPlayer();
  late String _recordId = widget.recordId ?? _newId();
  late DateTime _createdAt = widget.createdAt ?? DateTime.now().toUtc();
  GoPlacementMode _placementMode = GoPlacementMode.automatic;
  bool _thinking = false;
  bool _suspended = false;
  bool _modal = false;
  bool _leaving = false;
  String? _message;
  int _job = 0;
  Timer? _aiTimer;

  GoPlacementMode get _effectivePlacementMode =>
      resolveGomokuPlacementMode(_placementMode);

  bool get _isAi => widget.aiLevel != null && !widget.readOnly;
  Side get _humanColor => _session.colorForPlayer(widget.humanSide);
  int get _protectedOpening => _isAi && widget.humanSide == Side.white
      ? (_session.variant.competitive ? 3 : 1)
      : 0;
  bool get _canUndo =>
      !widget.readOnly &&
      (_session.resigned || _session.actionCount > _protectedOpening);
  bool get _canAct =>
      !widget.readOnly &&
      !_session.gameOver &&
      !_leaving &&
      !_modal &&
      !_suspended &&
      (!_isAi || _session.actor == widget.humanSide);
  bool get _canPlace => _canAct && _session.acceptsPlacement;

  static String _newId() => 'gomoku-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPlacement();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _persist();
      _driveAi();
    });
  }

  Future<void> _loadPlacement() async {
    final mode = await GoPlacementPreferences.load();
    if (mounted) setState(() => _placementMode = mode);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelAi();
    unawaited(_ai.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Rebuild on resume even when it is the human's turn and AI stays idle.
    setState(() {
      _suspended = state != AppLifecycleState.resumed;
      if (_suspended) _cancelAi();
    });
    if (!_suspended) _driveAi();
  }

  void _cancelAi() {
    _aiTimer?.cancel();
    _aiTimer = null;
    _job++;
    _ai.cancel();
    _thinking = false;
  }

  Future<void> _driveAi() async {
    if (!_isAi ||
        !mounted ||
        _leaving ||
        _thinking ||
        _suspended ||
        _modal ||
        _session.gameOver ||
        _session.actor == widget.humanSide) {
      return;
    }
    final job = ++_job;
    final revision = _session.revision;
    var advanced = false;
    setState(() => _thinking = true);
    try {
      final result = await _ai.decide(_session, level: widget.aiLevel!);
      if (!mounted ||
          job != _job ||
          revision != _session.revision ||
          _suspended ||
          _modal ||
          _session.gameOver) {
        return;
      }
      if (result != null && _session.applyAction(result)) {
        advanced = true;
        setState(() {
          _thinking = false;
          _message = null;
        });
        await _persist();
      } else {
        setState(() => _message = _ai.failureReason ?? 'AI 未能落子，请重试');
      }
    } catch (error) {
      if (mounted && job == _job) {
        setState(() => _message = 'AI 思考失败：$error');
      }
    } finally {
      if (mounted && job == _job) setState(() => _thinking = false);
      if (advanced &&
          mounted &&
          job == _job &&
          !_session.gameOver &&
          _session.actor != widget.humanSide) {
        _aiTimer?.cancel();
        _aiTimer = Timer(const Duration(milliseconds: 250), () {
          _aiTimer = null;
          if (mounted && job == _job) _driveAi();
        });
      }
    }
  }

  void _exchange(bool exchange) {
    if (!_canAct || !_session.exchangeColors(exchange)) return;
    setState(() => _message = null);
    _persist();
    _driveAi();
  }

  void _declare(int count) {
    if (!_canAct || !_session.declareProposals(count)) return;
    setState(() => _message = null);
    _persist();
    _driveAi();
  }

  Future<void> _pass() async {
    if (!_canAct || !_session.canPass) return;
    final accepted = await _confirm('停一手', '确认放弃本次行棋权？双方连续停一手将判和棋。');
    if (!mounted) return;
    setState(() {});
    if (accepted && _session.pass()) {
      setState(() => _message = null);
      await _persist();
    }
    _driveAi();
  }

  void _place(Cell cell) {
    if (!_canPlace) return;
    if (!_session.place(cell)) {
      setState(() => _message = _session.rejectionReason(cell) ?? '无法在这里落子');
      return;
    }
    setState(() => _message = null);
    _persist();
    _driveAi();
  }

  Future<void> _persist() async {
    if (widget.readOnly) return;
    final record = GomokuRecord(
      id: _recordId,
      createdAt: _createdAt,
      session: _session,
      aiLevel: widget.aiLevel,
      humanSide: widget.humanSide,
    );
    try {
      await GomokuStorage.save(record);
    } catch (error) {
      if (mounted) setState(() => _message = '自动保存失败：$error');
    }
  }

  Future<void> _playRecord() async {
    if (_modal || _leaving) return;
    setState(() {
      _cancelAi();
      _modal = true;
    });
    try {
      final replay = GomokuRecordReplay(
        GomokuRecord(id: _recordId, createdAt: _createdAt, session: _session),
      );
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => RecordPlaybackPage(record: replay)),
      );
    } catch (error) {
      if (mounted) setState(() => _message = '无法播放棋谱：$error');
    } finally {
      if (mounted) {
        setState(() => _modal = false);
        _driveAi();
      }
    }
  }

  Future<void> _undo() async {
    if (!_canUndo || _modal) return;
    _cancelAi();
    _session.undo();
    if (_isAi) {
      while (_session.actor != widget.humanSide &&
          _session.actionCount > _protectedOpening) {
        if (!_session.undo()) break;
      }
    }
    setState(() => _message = null);
    await _persist();
    _driveAi();
  }

  Future<bool> _confirm(String title, String content) async {
    _modal = true;
    setState(_cancelAi);
    final accepted = await showDialog<bool>(
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
    );
    _modal = false;
    return accepted == true;
  }

  Future<void> _resign() async {
    final side = _isAi ? _humanColor : _session.colorForPlayer(_session.actor);
    final accepted = await _confirm('认输', '${side.label}确认认输吗？');
    if (!mounted) return;
    if (accepted && _session.resign(side)) {
      setState(() => _message = null);
      await _persist();
    } else {
      setState(() {});
    }
    _driveAi();
  }

  Future<void> _restart() async {
    final accepted = await _confirm('重新开始', '当前对局已自动保存，确认开始新的对局吗？');
    if (!mounted) return;
    if (accepted) {
      setState(() {
        _session.reset();
        _recordId = _newId();
        _createdAt = DateTime.now().toUtc();
        _message = null;
      });
      await _persist();
    } else {
      setState(() {});
    }
    _driveAi();
  }

  String get _status => _session.gameOver
      ? _session.resultLabel
      : _thinking
      ? 'AI 正在思考…'
      : _session.variant.competitive
      ? '${_session.phaseLabel}${_isAi ? ' · ${_session.actor == widget.humanSide ? '你' : 'AI'}' : ''}'
      : '轮到${_session.turn.label}${_isAi ? ' · ${_session.actor == widget.humanSide ? '你' : 'AI'}' : ''}';

  @override
  Widget build(BuildContext context) => PopScope<void>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) {
        // A popped route stays mounted during its exit animation.
        _leaving = true;
        _cancelAi();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(_session.variant.label),
        actions: [
          IconButton(
            tooltip: '播放棋谱',
            onPressed: _modal ? null : _playRecord,
            icon: const Icon(Icons.play_circle_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: GomokuMatchLayout(
          header: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(_status, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '15×15 · ${_session.variant.label} · ${_session.moves.length} 手',
                  ),
                  if (_isAi)
                    Text(
                      'Rapfi · ${widget.aiLevel!.label} · 你执${_humanColor.label}${_session.exchanged ? '（已交换）' : ''}',
                    ),
                  if (_thinking) const LinearProgressIndicator(),
                  if (_message != null) Text(_message!),
                ],
              ),
            ),
          ),
          board: GomokuBoard(
            session: _session,
            onCell: _place,
            enabled: _canPlace,
            placementMode: _effectivePlacementMode,
          ),
          footer: Column(
            children: [
              const SizedBox(height: 8),
              if (widget.readOnly)
                const Text('旧规则存档 · 仅供查看')
              else ...[
                GomokuOpeningPanel(
                  session: _session,
                  enabled: _canAct,
                  onExchange: _exchange,
                  onDeclare: _declare,
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    if (_session.variant.competitive)
                      TextButton(
                        onPressed: _canAct && _session.canPass ? _pass : null,
                        child: const Text('停一手'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _canUndo && !_modal ? _undo : null,
                      icon: const Icon(Icons.undo),
                      label: const Text('悔棋'),
                    ),
                    TextButton.icon(
                      onPressed: !_session.gameOver && !_modal ? _resign : null,
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('认输'),
                    ),
                    TextButton.icon(
                      onPressed: !_modal ? _restart : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重开'),
                    ),
                    if (_isAi &&
                        !_thinking &&
                        !_session.gameOver &&
                        _session.actor != widget.humanSide)
                      TextButton(
                        onPressed: _driveAi,
                        child: const Text('重试 AI'),
                      ),
                  ],
                ),
              ],
              if (!widget.readOnly) ...[
                const SizedBox(height: 8),
                Text(
                  '自动保存 · 落子：${_effectivePlacementMode.label}\n${gomokuPlacementHint(_placementMode)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
