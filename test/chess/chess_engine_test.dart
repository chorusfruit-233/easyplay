import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/chess/chess_match_controller.dart';
import 'package:easyplay/chess/engine/chess_engine.dart';
import 'package:easyplay/chess/engine/stockfish_runtime.dart';
import 'package:easyplay/chess/engine/stockfish_io.dart';

class FakeUci implements StockfishTransport {
  final output = StreamController<String>.broadcast();
  final commands = <String>[];
  bool searching = false, closed = false;
  String? autoMove = 'e2e4';
  @override
  Stream<String> get lines => output.stream;
  @override
  Future<void> start() async {
    closed = false;
  }

  @override
  Future<void> send(String command) async {
    commands.add(command);
    if (command == 'uci') output.add('uciok');
    if (command == 'isready') output.add('readyok');
    if (command.startsWith('go ')) {
      searching = true;
      if (autoMove != null) output.add('bestmove $autoMove');
    }
    if (command == 'stop') {
      searching = false;
      output.add('bestmove e2e4');
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    searching = false;
  }
}

class DeferredEngine implements ChessEngine {
  Completer<ChessMove>? pending;
  int stops = 0, disposed = 0;
  @override
  Future<void> start() async {}
  @override
  Future<void> newGame() async {
    await stop();
  }

  @override
  Future<ChessMove> bestMove(ChessPosition position, ChessEngineLimits limits) {
    pending = Completer<ChessMove>();
    return pending!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed++;
    await stop();
  }
}

void main() {
  test('UCI handshake, configuration, legal bestmove and new game', () async {
    final io = FakeUci();
    final engine = StockfishEngine(io);
    final move = await engine.bestMove(
      ChessPosition.initial(),
      ChessAiLevel.normal.limits,
    );
    expect(moveToUci(move), 'e2e4');
    expect(
      io.commands,
      containsAllInOrder([
        'uci',
        'setoption name Threads value 1',
        'setoption name Hash value 16',
        'isready',
      ]),
    );
    expect(
      io.commands.any((c) => c.startsWith('position fen rnbqkbnr/')),
      true,
    );
    expect(io.commands, contains('go movetime 400'));
    await engine.newGame();
    expect(io.commands, contains('ucinewgame'));
    await engine.dispose();
    expect(io.closed, true);
  });
  test('stop drains old bestmove and permits the next search', () async {
    final io = FakeUci()..autoMove = null;
    final engine = StockfishEngine(io);
    final future = engine.bestMove(
      ChessPosition.initial(),
      ChessAiLevel.maximum.limits,
    );
    final cancelled = expectLater(future, throwsA(isA<ChessSearchCancelled>()));
    while (!io.searching) {
      await Future<void>.delayed(Duration.zero);
    }
    await engine.stop();
    await cancelled;
    expect(io.commands, contains('stop'));
    io.autoMove = 'd2d4';
    expect(
      moveToUci(
        await engine.bestMove(
          ChessPosition.initial(),
          ChessAiLevel.easy.limits,
        ),
      ),
      'd2d4',
    );
    await engine.dispose();
  });
  test('illegal engine output never bypasses rules', () async {
    final io = FakeUci()..autoMove = 'e2e5';
    final engine = StockfishEngine(io);
    await expectLater(
      engine.bestMove(ChessPosition.initial(), ChessAiLevel.easy.limits),
      throwsStateError,
    );
    await engine.dispose();
  });
  test(
    'AI undo during search drops stale result and restores player turn',
    () async {
      final engine = DeferredEngine();
      final controller = ChessMatchController(engine: engine);
      expect(controller.play(parseUciMove('e2e4')), true);
      final stale = engine.pending!;
      await controller.undo();
      expect(controller.session.fen, exportFen(ChessPosition.initial()));
      stale.complete(parseUciMove('e7e5'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.session.moves, isEmpty);
      expect(controller.session.turn, Side.white);
      expect(controller.thinking, false);
      expect(engine.stops, greaterThan(0));
      controller.dispose();
    },
  );
  test(
    'AI pair undo, playing black, resignation and dispose invalidate replies',
    () async {
      final engine = DeferredEngine();
      final controller = ChessMatchController(
        engine: engine,
        humanSide: Side.black,
      );
      final first = controller.runAi();
      engine.pending!.complete(parseUciMove('e2e4'));
      await first;
      expect(controller.session.turn, Side.black);
      controller.play(parseUciMove('e7e5'));
      engine.pending!.complete(parseUciMove('g1f3'));
      await Future<void>.delayed(Duration.zero);
      await controller.undo();
      expect(controller.session.moves.length, 1);
      expect(controller.session.turn, Side.black);
      controller.play(parseUciMove('c7c5'));
      final stale = engine.pending!;
      await controller.resign();
      stale.complete(parseUciMove('g1f3'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.session.result?.reason, ChessEndReason.resignation);
      expect(controller.session.moves.length, 2);
      controller.dispose();
      expect(engine.disposed, 1);
    },
  );
  test('restart/exit discard an old generation', () async {
    final engine = DeferredEngine();
    final controller = ChessMatchController(engine: engine);
    controller.play(parseUciMove('e2e4'));
    final stale = engine.pending!;
    await controller.restart();
    stale.complete(parseUciMove('e7e5'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.session.moves, isEmpty);
    controller.play(parseUciMove('d2d4'));
    final leaving = engine.pending!;
    controller.dispose();
    leaving.complete(parseUciMove('d7d5'));
    await Future<void>.delayed(Duration.zero);
    expect(engine.disposed, 1);
  });
  final native = Platform.environment['STOCKFISH_TEST_EXECUTABLE'];
  test(
    'real native UCI: handshake, legal move, stop, restart and process disposal',
    () async {
      final engine = StockfishEngine(
        ProcessStockfishTransport(executable: native!),
      );
      final session = ChessSession();
      final move = await engine.bestMove(
        session.position,
        ChessAiLevel.beginner.limits,
      );
      expect(session.applyMove(move), true);
      final cancelled = engine.bestMove(
        session.position,
        ChessAiLevel.maximum.limits,
      );
      final expectation = expectLater(
        cancelled,
        throwsA(isA<ChessSearchCancelled>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.stop();
      await expectation;
      await engine.newGame();
      expect(
        ChessSession().isLegalMove(
          await engine.bestMove(
            ChessPosition.initial(),
            ChessAiLevel.beginner.limits,
          ),
        ),
        true,
      );
      await engine.dispose();
    },
    skip: native == null
        ? 'Set STOCKFISH_TEST_EXECUTABLE to a native Stockfish 19 executable'
        : false,
  );
}
