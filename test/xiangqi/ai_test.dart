import 'dart:async';
import 'dart:io';
import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:easyplay/xiangqi/xiangqi_match_controller.dart';
import 'package:easyplay/xiangqi/engine/xiangqi_engine.dart';
import 'package:easyplay/xiangqi/engine/pikafish_runtime.dart';
import 'package:easyplay/xiangqi/engine/pikafish_io.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingEngine implements XiangqiEngine {
  Completer<XiangqiMove>? pending;
  bool disposed = false;
  @override
  Future<void> start() async {}
  @override
  Future<void> newGame() async {
    await stop();
  }

  @override
  Future<XiangqiMove> bestMove(
    XiangqiPosition p,
    List<XiangqiMove> history,
    XiangqiEngineLimits limits,
  ) {
    pending = Completer<XiangqiMove>();
    return pending!.future;
  }

  @override
  Future<void> stop() async {
    // Simulate an engine which returns its last result after cancellation.
    if (pending?.isCompleted == false) {
      pending!.complete(parseXiangqiUciMove('b9c7'));
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await stop();
  }
}

void main() {
  test('six difficulty levels use skills and time rather than chess Elo', () {
    expect(XiangqiAiLevel.values.length, 6);
    expect(XiangqiAiLevel.beginner.skill, 0);
    expect(XiangqiAiLevel.maximum.skill, 20);
  });
  test('undo discards an old search and returns to the player turn', () async {
    final engine = PendingEngine();
    final controller = XiangqiMatchController(engine: engine);
    expect(controller.play(parseXiangqiUciMove('h2e2')), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(controller.thinking, isTrue);
    await controller.undo();
    expect(controller.session.moves, isEmpty);
    expect(controller.session.turn, XiangqiSide.red);
    expect(controller.thinking, isFalse);
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(engine.disposed, isTrue);
  });
  test('an illegal engine move never changes the session', () async {
    final engine = PendingEngine();
    final controller = XiangqiMatchController(engine: engine);
    controller.play(parseXiangqiUciMove('h2e2'));
    await Future<void>.delayed(Duration.zero);
    engine.pending!.complete(parseXiangqiUciMove('a9a0'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.session.moves.length, 1);
    expect(controller.error, isNotNull);
    controller.dispose();
  });
  final executable = Platform.environment['PIKAFISH_TEST_EXECUTABLE'];
  test(
    'real pinned native NNUE red/black search, history, stop and new game',
    () async {
      final transport = ProcessPikafishTransport(
        executable: executable!,
        workingDirectory: '${Directory.current.path}/assets/pikafish',
      );
      final engine = PikafishEngine(transport);
      final session = XiangqiSession();
      try {
        await engine.start();
        final red = await engine.bestMove(
          session.position,
          session.moves,
          const XiangqiEngineLimits(movetime: 150),
        );
        expect(session.applyMove(red), isTrue);
        final black = await engine.bestMove(
          session.position,
          session.moves,
          const XiangqiEngineLimits(movetime: 150),
        );
        expect(session.applyMove(black), isTrue);
        final search = engine.bestMove(
          session.position,
          session.moves,
          const XiangqiEngineLimits(movetime: 5000),
        );
        final cancelled = expectLater(
          search,
          throwsA(isA<XiangqiSearchCancelled>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await engine.stop();
        await cancelled;
        await engine.newGame();
      } finally {
        await engine.dispose();
      }
    },
    skip: executable == null
        ? 'Set PIKAFISH_TEST_EXECUTABLE to a pinned native executable'
        : false,
  );
}
