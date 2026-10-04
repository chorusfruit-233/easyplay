import 'dart:async';

import '../xiangqi.dart';
import 'xiangqi_engine.dart';
import 'pikafish_stub.dart'
    if (dart.library.io) 'pikafish_io.dart'
    if (dart.library.js_interop) 'pikafish_web.dart'
    as platform;

XiangqiEngine createXiangqiEngine() =>
    PikafishEngine(platform.createPikafishTransport());

/// One UCI search at a time. stop drains bestmove before another search starts.
class PikafishEngine implements XiangqiEngine {
  PikafishEngine(this.transport);
  final PikafishTransport transport;
  StreamSubscription<String>? _subscription;
  final _waiters = <_UciWaiter>[];
  Future<void>? _starting;
  Future<XiangqiMove>? _search;
  Future<String>? _best;
  bool _ready = false, _disposed = false;
  int _generation = 0;

  void _line(String line) {
    if (line.startsWith('info string CRITICAL ERROR')) {
      _fail(StateError(line));
      return;
    }
    for (final waiter in List.of(_waiters)) {
      if (waiter.matches(line)) {
        _waiters.remove(waiter);
        waiter.completer.complete(line);
      }
    }
  }

  void _fail(Object error) {
    _ready = false;
    for (final waiter in List.of(_waiters)) {
      waiter.completer.completeError(error);
    }
    _waiters.clear();
  }

  Future<String> _wait(bool Function(String) matches, {int seconds = 120}) {
    final waiter = _UciWaiter(matches);
    _waiters.add(waiter);
    return waiter.completer.future
        .timeout(Duration(seconds: seconds))
        .whenComplete(() => _waiters.remove(waiter));
  }

  Future<void> _exchange(String command, String response) async {
    final answer = _wait((line) => line == response);
    // Attach the listener before issuing a command; native events may arrive
    // before the MethodChannel response does.
    await Future.wait([transport.send(command), answer]);
  }

  @override
  Future<void> start() {
    if (_disposed) return Future.error(StateError('引擎已关闭'));
    if (_ready) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    _subscription ??= transport.lines.listen(
      _line,
      onError: _fail,
      onDone: () => _fail(StateError('Pikafish 已退出')),
    );
    await transport.start();
    try {
      await _exchange('uci', 'uciok');
      await transport.send('setoption name Threads value 1');
      await transport.send('setoption name Hash value 16');
      await _exchange('isready', 'readyok');
      if (_disposed) throw const XiangqiSearchCancelled();
      _ready = true;
    } catch (_) {
      await transport.close();
      rethrow;
    }
  }

  @override
  Future<XiangqiMove> bestMove(
    XiangqiPosition position,
    List<XiangqiMove> history,
    XiangqiEngineLimits limits,
  ) {
    if (_search != null) return Future.error(StateError('引擎仍在搜索'));
    final generation = _generation;
    final future = _bestMove(
      position,
      List.unmodifiable(history),
      limits,
      generation,
    );
    _search = future.whenComplete(() {
      _search = null;
      _best = null;
    });
    return _search!;
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw const XiangqiSearchCancelled();
    }
  }

  Future<XiangqiMove> _bestMove(
    XiangqiPosition p,
    List<XiangqiMove> history,
    XiangqiEngineLimits limits,
    int generation,
  ) async {
    await start();
    _check(generation);
    await transport.send(
      'setoption name Skill Level value ${limits.skill.clamp(0, 20)}',
    );
    await transport.send('setoption name UCI_LimitStrength value false');
    await _exchange('isready', 'readyok');
    _check(generation);
    final initial = limits.initialPosition ?? XiangqiPosition.initial();
    final replay = XiangqiSession(position: initial);
    for (final move in history) {
      if (!replay.applyMove(move)) throw StateError('无效的 AI 着法历史');
    }
    if (exportXiangqiFen(replay.position) != exportXiangqiFen(p)) {
      throw StateError('AI 初始局面和历史与当前局面不一致');
    }
    final base =
        exportXiangqiFen(initial) == exportXiangqiFen(XiangqiPosition.initial())
        ? 'startpos'
        : 'fen ${exportXiangqiFen(initial)}';
    final moves = history.isEmpty
        ? ''
        : ' moves ${history.map(xiangqiMoveToUci).join(' ')}';
    await transport.send('position $base$moves');
    _check(generation);
    final response = _wait((line) => line.startsWith('bestmove '));
    _best = response;
    await Future.wait([
      transport.send('go movetime ${limits.movetime.clamp(50, 5000)}'),
      response,
    ]);
    _check(generation);
    final line = await response;
    final move = parseXiangqiUciMove(line.split(RegExp(r'\s+'))[1]);
    if (!XiangqiMoveGenerator.legalMoves(p, from: move.from).contains(move)) {
      throw StateError('Pikafish 返回非法着法：${xiangqiMoveToUci(move)}');
    }
    return move;
  }

  @override
  Future<void> stop() async {
    _generation++;
    final search = _search;
    // Observe cancellation before completing the pending bestmove future.
    final settled = search?.then<void>((_) {}, onError: (Object _) {});
    final best = _best;
    if (best != null) {
      try {
        await transport.send('stop');
        await best.timeout(const Duration(seconds: 3));
      } catch (_) {
        _fail(const XiangqiSearchCancelled());
        await transport.close();
      }
    }
    await settled;
  }

  @override
  Future<void> newGame() async {
    await stop();
    await start();
    await transport.send('ucinewgame');
    await _exchange('isready', 'readyok');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _fail(const XiangqiSearchCancelled());
    await stop();
    try {
      await _starting;
    } catch (_) {
      /* Startup may be cancelled. */
    }
    await transport.close();
    await _subscription?.cancel();
  }
}

class _UciWaiter {
  _UciWaiter(this.matches);
  final bool Function(String) matches;
  final completer = Completer<String>();
}
