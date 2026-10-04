import 'dart:async';
import 'package:flutter/foundation.dart';
import 'xiangqi.dart';
import 'engine/xiangqi_engine.dart';

/// Owns a disposable local/AI match; asynchronous results are generation-bound.
class XiangqiMatchController extends ChangeNotifier {
  XiangqiMatchController({
    XiangqiSession? session,
    this.engine,
    this.humanSide = XiangqiSide.red,
    this.level = XiangqiAiLevel.normal,
  }) : session = session ?? XiangqiSession();
  XiangqiSession session;
  final XiangqiEngine? engine;
  final XiangqiSide humanSide;
  final XiangqiAiLevel level;
  bool thinking = false, _disposed = false, _changing = false;
  String? error;
  int _generation = 0;
  Future<void>? _stopping;
  bool get isAi => engine != null;
  bool get canPlay =>
      !_changing &&
      !thinking &&
      !session.gameOver &&
      (!isAi || session.turn == humanSide);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool play(XiangqiMove move) {
    if (!canPlay || !session.applyMove(move)) return false;
    error = null;
    _notify();
    unawaited(runAi());
    return true;
  }

  Future<void> runAi() async {
    if (_disposed ||
        _changing ||
        engine == null ||
        thinking ||
        session.gameOver ||
        session.turn == humanSide) {
      return;
    }
    final generation = _generation;
    thinking = true;
    error = null;
    _notify();
    try {
      if (_stopping != null) await _stopping;
      if (_disposed || generation != _generation) return;
      final move = await engine!.bestMove(
        session.position,
        session.moves,
        XiangqiEngineLimits(
          skill: level.skill,
          movetime: level.movetime,
          initialPosition: session.initialPosition,
        ),
      );
      if (_disposed || generation != _generation) return;
      if (!session.applyMove(move)) throw StateError('引擎返回的着法不合法');
      if (session.gameOver) await engine!.stop();
    } on XiangqiSearchCancelled {
      /* The caller changed or closed the match. */
    } catch (exception) {
      if (!_disposed && generation == _generation) error = 'AI 暂不可用：$exception';
    } finally {
      if (!_disposed && generation == _generation) {
        thinking = false;
        _notify();
      }
    }
  }

  Future<void> undo() async {
    if (_changing || !session.canUndo) return;
    _changing = true;
    _generation++;
    thinking = false;
    _notify();
    await engine?.stop();
    if (_disposed) return;
    final count = session.moves.length;
    session.undo();
    if (isAi) {
      while (session.canUndo &&
          (session.moves.length >= count || session.turn != humanSide)) {
        session.undo();
      }
    }
    _changing = false;
    error = null;
    _notify();
    await runAi();
  }

  Future<void> restart() async {
    if (_changing) return;
    _changing = true;
    _generation++;
    thinking = false;
    _notify();
    try {
      await engine?.newGame();
      if (_disposed) return;
      session.dispose();
      session = XiangqiSession();
      error = null;
    } catch (exception) {
      if (!_disposed) error = '引擎重启失败：$exception';
    } finally {
      _changing = false;
      _notify();
    }
    await runAi();
  }

  Future<void> resign() async {
    _generation++;
    thinking = false;
    session.resign(isAi ? humanSide : session.turn);
    _notify();
    await engine?.stop();
  }

  Future<void> agreeDraw() async {
    _generation++;
    thinking = false;
    session.agreeDraw();
    _notify();
    await engine?.stop();
  }

  Future<void> suspend() async {
    _generation++;
    thinking = false;
    _notify();
    _stopping = engine?.stop();
    await _stopping;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(engine?.dispose());
    session.dispose();
    super.dispose();
  }
}
