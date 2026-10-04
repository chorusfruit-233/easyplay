import 'package:flutter/material.dart';

import '../../game_session.dart' show Cell, Side, SideX;
import '../../go_placement.dart';
import '../gomoku_ai.dart';
import '../gomoku_session.dart';
import '../gomoku_storage.dart';
import 'gomoku_board.dart';

class GomokuGamePage extends StatefulWidget {
  const GomokuGamePage({
    super.key,
    required this.session,
    this.recordId,
    this.createdAt,
    this.aiLevel,
    this.humanSide = Side.black,
    this.ai,
  });

  final GomokuSession session;
  final String? recordId;
  final DateTime? createdAt;
  final GomokuAiLevel? aiLevel;
  final Side humanSide;
  final GomokuAi? ai;

  @override
  State<GomokuGamePage> createState() => _GomokuGamePageState();
}

class _GomokuGamePageState extends State<GomokuGamePage>
    with WidgetsBindingObserver {
  late final GomokuSession _session = widget.session;
  late final GomokuAi _ai = widget.ai ?? GomokuAi();
  late String _recordId = widget.recordId ?? _newId();
  late DateTime _createdAt = widget.createdAt ?? DateTime.now().toUtc();
  GoPlacementMode _placementMode = GoPlacementMode.automatic;
  bool _thinking = false;
  bool _suspended = false;
  bool _modal = false;
  bool _leaving = false;
  String? _message;
  int _job = 0;

  bool get _isAi => widget.aiLevel != null;
  int get _protectedOpening => _isAi && widget.humanSide == Side.white ? 1 : 0;
  bool get _canUndo =>
      _session.resigned || _session.moves.length > _protectedOpening;
  bool get _canPlace =>
      !_session.gameOver &&
      !_leaving &&
      !_modal &&
      !_suspended &&
      (!_isAi || _session.turn == widget.humanSide);

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _suspended = state != AppLifecycleState.resumed;
    if (_suspended) {
      setState(_cancelAi);
    } else {
      _driveAi();
    }
  }

  void _cancelAi() {
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
        _session.turn == widget.humanSide) {
      return;
    }
    final job = ++_job;
    final revision = _session.revision;
    setState(() => _thinking = true);
    try {
      final result = await _ai.search(_session, level: widget.aiLevel!);
      if (!mounted ||
          job != _job ||
          revision != _session.revision ||
          _suspended ||
          _modal ||
          _session.gameOver) {
        return;
      }
      if (result != null && _session.place(result.cell)) {
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
    }
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

  Future<void> _undo() async {
    if (!_canUndo || _modal) return;
    _cancelAi();
    _session.undo();
    if (_isAi) {
      while (_session.turn != widget.humanSide &&
          _session.moves.length > _protectedOpening) {
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
    final side = _isAi ? widget.humanSide : _session.turn;
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
      : '轮到${_session.turn.label}${_isAi ? ' · ${_session.turn == widget.humanSide ? '你' : 'AI'}' : ''}';

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
      appBar: AppBar(title: Text(_session.variant.label)),
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
                      '人机 · ${widget.aiLevel!.label} · 你执${widget.humanSide.label}',
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
            placementMode: _placementMode,
          ),
          footer: Column(
            children: [
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
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
                      _ai.failureReason == null &&
                      !_session.gameOver &&
                      _session.turn != widget.humanSide)
                    TextButton(onPressed: _driveAi, child: const Text('重试 AI')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '自动保存 · 落子：${_placementMode.label}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
