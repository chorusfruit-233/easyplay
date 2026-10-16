import 'dart:async';

import 'package:easyplay/ai/ai_duel_controller.dart';
import 'package:easyplay/game_session.dart' show Side;
import 'package:flutter_test/flutter_test.dart';

class ControlledDuel extends AiDuelController<int> {
  ControlledDuel({super.initiallyPaused, this.limit = 20});

  final int limit;
  final searches = <Completer<int?>>[];
  final searchedSides = <Side>[];
  final savedMoves = <int>[];
  int cancellations = 0;
  int _moves = 0;
  int _revision = 0;

  @override
  Side get turn => _moves.isEven ? Side.black : Side.white;
  @override
  int get revision => _revision;
  @override
  int get moveCount => _moves;
  @override
  bool get gameOver => _moves >= limit;
  @override
  String get resultLabel => '黑方获胜';

  @override
  Future<int?> search() {
    searchedSides.add(turn);
    final pending = Completer<int?>();
    searches.add(pending);
    return pending.future;
  }

  void finish([int? move = 1]) => searches.last.complete(move);

  @override
  void cancelSearch() => cancellations++;
  @override
  bool applyMove(int move) {
    if (move != 1) return false;
    _moves++;
    _revision++;
    return true;
  }

  @override
  bool undoPosition() {
    if (_moves == 0) return false;
    _moves--;
    _revision++;
    return true;
  }

  @override
  void resetPosition() {
    _moves = 0;
    _revision++;
  }

  @override
  Future<void> savePosition() async => savedMoves.add(_moves);
}

void main() {
  // Widget tests supply a fake clock without introducing a production timer
  // abstraction. These cases exercise real pending futures and late results.
  testWidgets('autoplay alternates sides and waits for the move animation', (
    tester,
  ) async {
    final duel = ControlledDuel();
    addTearDown(duel.dispose);
    duel.start();
    await tester.pump(Duration.zero);
    expect(duel.searchedSides, [Side.black]);
    duel.finish();
    await tester.pump();
    expect(duel.moveCount, 1);
    expect(duel.savedMoves, [0, 1]);
    await tester.pump(const Duration(milliseconds: 699));
    expect(duel.searches, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(duel.searchedSides, [Side.black, Side.white]);
    duel.finish();
    await tester.pump();
    expect(duel.moveCount, 2);
    duel.dispose();
  });

  testWidgets('pause rejects a late result; step commits exactly one move', (
    tester,
  ) async {
    final duel = ControlledDuel();
    addTearDown(duel.dispose);
    duel.start();
    await tester.pump(Duration.zero);
    duel.pause();
    duel.finish();
    await tester.pump(const Duration(seconds: 2));
    expect(duel.moveCount, 0);
    expect(duel.thinking, isFalse);
    expect(duel.savedMoves, [0]);
    duel.step();
    expect(duel.canStep, isFalse);
    duel.step();
    expect(duel.searches, hasLength(2));
    duel.finish();
    await tester.pump(const Duration(seconds: 2));
    expect(duel.moveCount, 1);
    expect(duel.paused, isTrue);
    expect(duel.searches, hasLength(2));
    duel.resume();
    await tester.pump(duel.moveInterval);
    expect(duel.searchedSides.last, Side.white);
    duel.dispose();
  });

  testWidgets('background cancels work and resumes only a running duel', (
    tester,
  ) async {
    final duel = ControlledDuel();
    addTearDown(duel.dispose);
    duel.start();
    await tester.pump(Duration.zero);
    duel.setForeground(false);
    duel.finish();
    await tester.pump(const Duration(seconds: 3));
    expect(duel.moveCount, 0);
    expect(duel.searches, hasLength(1));
    duel.setForeground(true);
    await tester.pump(duel.moveInterval);
    expect(duel.thinking, isTrue);
    duel.finish();
    await tester.pump();
    expect(duel.moveCount, 1);
    duel.pause();
    duel.setForeground(false);
    duel.setForeground(true);
    await tester.pump(const Duration(seconds: 3));
    expect(duel.paused, isTrue);
    expect(duel.searches, hasLength(2));
  });

  testWidgets('undo and restart invalidate work without reapplying it', (
    tester,
  ) async {
    final duel = ControlledDuel();
    addTearDown(duel.dispose);
    duel.start();
    await tester.pump(Duration.zero);
    duel.finish();
    await tester.pump();
    await tester.pump(duel.moveInterval);
    duel.undo();
    duel.finish();
    await tester.pump(const Duration(seconds: 2));
    expect(duel.moveCount, 0);
    expect(duel.paused, isTrue);
    duel.step();
    final stale = duel.searches.last;
    duel.restart();
    await tester.pump(Duration.zero);
    stale.complete(1);
    await tester.pump();
    expect(duel.moveCount, 0);
    expect(duel.thinking, isTrue);
    duel.finish();
    await tester.pump();
    expect(duel.moveCount, 1);
    duel.dispose();
  });

  for (final stopped in [false, true]) {
    testWidgets(
      '${stopped ? 'stop' : 'dispose'} rejects a late result and save',
      (tester) async {
        final duel = ControlledDuel();
        duel.start();
        await tester.pump(Duration.zero);
        if (stopped) {
          duel.stop();
        } else {
          duel.dispose();
        }
        duel.finish();
        await tester.pump(const Duration(seconds: 2));
        expect(duel.moveCount, 0);
        expect(duel.savedMoves, [0]);
        expect(duel.searches, hasLength(1));
        if (stopped) duel.dispose();
      },
    );
  }

  testWidgets('game over stops the loop; undo allows further observation', (
    tester,
  ) async {
    final duel = ControlledDuel(limit: 1);
    addTearDown(duel.dispose);
    duel.start();
    await tester.pump(Duration.zero);
    duel.finish();
    await tester.pump(const Duration(seconds: 3));
    expect(duel.gameOver, isTrue);
    expect(duel.searches, hasLength(1));
    duel.resume();
    duel.step();
    await tester.pump(const Duration(seconds: 3));
    expect(duel.searches, hasLength(1));
    duel.undo();
    expect(duel.gameOver, isFalse);
    expect(duel.canStep, isTrue);
  });

  for (final failure in ['null', 'illegal', 'exception']) {
    testWidgets('$failure pauses autoplay rather than retrying endlessly', (
      tester,
    ) async {
      final duel = ControlledDuel();
      addTearDown(duel.dispose);
      duel.start();
      await tester.pump(Duration.zero);
      if (failure == 'exception') {
        duel.searches.last.completeError(StateError('failed'));
      } else {
        duel.finish(failure == 'null' ? null : 99);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(duel.paused, isTrue);
      expect(duel.error, isNotNull);
      expect(duel.moveCount, 0);
      expect(duel.searches, hasLength(1));
      duel.resume();
      await tester.pump(duel.moveInterval);
      duel.finish();
      await tester.pump();
      expect(duel.error, isNull);
      expect(duel.moveCount, 1);
      duel.dispose();
    });
  }
}
