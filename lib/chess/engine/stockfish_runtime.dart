import 'dart:async';

import '../chess.dart';
import 'chess_engine.dart';
import 'stockfish_stub.dart'
    if (dart.library.io) 'stockfish_io.dart'
    if (dart.library.js_interop) 'stockfish_web.dart'
    as platform;

ChessEngine createChessEngine() =>
    StockfishEngine(platform.createStockfishTransport());

/// One UCI search at a time. stop drains bestmove before another search starts.
class StockfishEngine implements ChessEngine {
  StockfishEngine(this.transport);
  final StockfishTransport transport;
  StreamSubscription<String>? _subscription;
  final _waiters = <_UciWaiter>[];
  Future<void>? _starting;
  Future<ChessMove>? _search;
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

  Future<String> _wait(bool Function(String) matches, {int seconds = 20}) {
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
      onDone: () => _fail(StateError('Stockfish 已退出')),
    );
    await transport.start();
    try {
      await _exchange('uci', 'uciok');
      await transport.send('setoption name Threads value 1');
      await transport.send('setoption name Hash value 16');
      await _exchange('isready', 'readyok');
      if (_disposed) throw const ChessSearchCancelled();
      _ready = true;
    } catch (_) {
      await transport.close();
      rethrow;
    }
  }

  @override
  Future<ChessMove> bestMove(ChessPosition position, ChessEngineLimits limits) {
    if (_search != null) return Future.error(StateError('引擎仍在搜索'));
    final generation = _generation;
    final future = _bestMove(position, limits, generation);
    _search = future.whenComplete(() {
      _search = null;
      _best = null;
    });
    return _search!;
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw const ChessSearchCancelled();
    }
  }

  Future<ChessMove> _bestMove(
    ChessPosition p,
    ChessEngineLimits limits,
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
    await transport.send('position fen ${exportFen(p)}');
    _check(generation);
    final response = _wait((line) => line.startsWith('bestmove '));
    _best = response;
    await Future.wait([
      transport.send('go movetime ${limits.movetime.clamp(50, 5000)}'),
      response,
    ]);
    _check(generation);
    final line = await response;
    final move = parseUciMove(line.split(RegExp(r'\s+'))[1]);
    if (!ChessMoveGenerator.legalMoves(p, from: move.from).contains(move)) {
      throw StateError('Stockfish 返回非法着法：${moveToUci(move)}');
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
        _fail(const ChessSearchCancelled());
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
    _fail(const ChessSearchCancelled());
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
