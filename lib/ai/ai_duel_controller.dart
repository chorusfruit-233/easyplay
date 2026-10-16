import 'dart:async';

import 'package:flutter/foundation.dart';

import '../game_session.dart' show Side;

/// Serializes spectator controls, lifecycle changes and cancellable AI work.
/// Rule checks and immutable save snapshots remain in the game adapters.
abstract class AiDuelController<M> extends ChangeNotifier {
  AiDuelController({
    bool initiallyPaused = false,
    this.moveInterval = const Duration(milliseconds: 700),
  }) : _paused = initiallyPaused;

  final Duration moveInterval;
  bool _paused;
  bool _thinking = false;
  bool _foreground = true;
  bool _started = false;
  bool _stopped = false;
  bool _disposed = false;
  int _job = 0;
  Timer? _timer;
  String? _error;
  String? _saveError;

  bool get paused => _paused;
  bool get thinking => _thinking;
  bool get foreground => _foreground;
  String? get error => _error;
  String? get saveError => _saveError;
  bool get canStep => _ready && _paused && !_thinking && !gameOver;
  bool get _ready => _started && !_stopped && !_disposed && _foreground;
  bool get _running => _ready && !_paused && !gameOver;

  Side get turn;
  int get revision;
  int get moveCount;
  bool get gameOver;
  String get resultLabel;
  Future<M?> search();
  void cancelSearch();
  bool applyMove(M move);
  bool undoPosition();
  void resetPosition();
  Future<void> savePosition();

  void start() {
    if (_started || _stopped || _disposed) return;
    _started = true;
    _persist();
    _schedule(Duration.zero);
  }

  void _schedule([Duration? delay]) {
    if (!_running || _thinking || _timer != null) return;
    _timer = Timer(delay ?? moveInterval, () {
      _timer = null;
      unawaited(_play());
    });
  }

  void _cancel() {
    _job++;
    _timer?.cancel();
    _timer = null;
    cancelSearch();
    _thinking = false;
  }

  void pause() {
    if (_disposed || _stopped) return;
    _paused = true;
    _cancel();
    notifyListeners();
  }

  void resume() {
    if (_disposed || _stopped || gameOver) return;
    _paused = false;
    _error = null;
    notifyListeners();
    _schedule();
  }

  void step() {
    if (canStep) unawaited(_play(singleStep: true));
  }

  void undo() {
    if (_disposed || _stopped) return;
    _cancel();
    _paused = true;
    _error = null;
    if (undoPosition()) _persist();
    notifyListeners();
  }

  void restart({bool paused = false}) {
    if (_disposed || _stopped) return;
    _cancel();
    resetPosition();
    _paused = paused;
    _error = null;
    _saveError = null;
    _persist();
    notifyListeners();
    _schedule(Duration.zero);
  }

  void setForeground(bool value) {
    if (_disposed || _stopped || value == _foreground) return;
    _foreground = value;
    if (!value) _cancel();
    notifyListeners();
    if (value) _schedule();
  }

  /// Called when the route pops, before its exit animation finishes.
  void stop() {
    if (_disposed || _stopped) return;
    _stopped = true;
    _cancel();
  }

  Future<void> _play({bool singleStep = false}) async {
    if (!_ready || _thinking || gameOver || (_paused && !singleStep)) return;
    final job = ++_job;
    final expectedRevision = revision;
    final expectedTurn = turn;
    _thinking = true;
    _error = null;
    notifyListeners();
    try {
      final move = await search();
      if (job != _job || !_ready) return;
      if (revision != expectedRevision || turn != expectedTurn) return;
      if (move == null || !applyMove(move)) {
        _paused = true;
        _error = 'AI 未能完成行棋，请重试或重开';
      } else {
        _persist();
      }
    } catch (_) {
      if (job == _job && _ready) {
        _paused = true;
        _error = 'AI 行棋失败，请重试或重开';
      }
    } finally {
      if (job == _job && !_disposed && !_stopped) {
        _thinking = false;
        notifyListeners();
        // Leave time for the preceding placement/capture animation to finish.
        _schedule();
      }
    }
  }

  void _persist() {
    // The adapter takes its snapshot synchronously, before yielding to storage.
    unawaited(
      savePosition().then(
        (_) {
          if (_disposed || _stopped || _saveError == null) return;
          _saveError = null;
          notifyListeners();
        },
        onError: (Object _) {
          if (_disposed || _stopped) return;
          _saveError = '保存失败，后续行棋时将重试';
          notifyListeners();
        },
      ),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    super.dispose();
  }
}
