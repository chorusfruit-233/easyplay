import 'dart:math';

import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:flutter_test/flutter_test.dart';

GomokuSession position(
  List<Cell> black,
  List<Cell> white, {
  GomokuVariant variant = GomokuVariant.freestyle,
}) {
  final session = GomokuSession(variant: variant);
  for (var index = 0; index < black.length; index++) {
    expect(session.place(black[index]), isTrue);
    if (index < white.length) expect(session.place(white[index]), isTrue);
  }
  return session;
}

void main() {
  test('opens in the center without touching the live session', () async {
    final session = GomokuSession();
    final before = session.toJson();
    final result = await GomokuAi().search(session, maxDepth: 1);
    expect(result!.cell, const Cell(7, 7));
    expect(session.toJson(), before);
  });

  for (final level in [GomokuAiLevel.intermediate, GomokuAiLevel.advanced]) {
    test('${level.label} takes its own win before blocking', () async {
      final session = position(
        const [Cell(7, 3), Cell(7, 4), Cell(7, 5), Cell(7, 6)],
        const [Cell(4, 3), Cell(4, 4), Cell(4, 5), Cell(4, 6)],
      );
      final before = session.toJson();
      final result = await GomokuAi().search(session, level: level);
      expect(const [Cell(7, 2), Cell(7, 7)], contains(result!.cell));
      final continuation = session.fork()..place(result.cell);
      expect(continuation.winner, Side.black);
      expect(session.toJson(), before);
    });

    test('${level.label} blocks the only immediate winning point', () async {
      final session = position(
        const [Cell(4, 2), Cell(10, 2), Cell(10, 4), Cell(12, 6)],
        const [Cell(4, 3), Cell(4, 4), Cell(4, 5), Cell(4, 6)],
      );
      final result = await GomokuAi().search(session, level: level);
      expect(result!.cell, const Cell(4, 7));
    });

    test(
      '${level.label} finds broken and diagonal immediate threats',
      () async {
        final broken = position(
          const [Cell(10, 1), Cell(10, 3), Cell(10, 5), Cell(12, 7)],
          const [Cell(6, 3), Cell(6, 4), Cell(6, 6), Cell(6, 7)],
        );
        final result = await GomokuAi().search(broken, level: level);
        expect(result!.cell, const Cell(6, 5));
        final diagonal = position(
          const [Cell(4, 4), Cell(10, 2), Cell(10, 4), Cell(12, 6)],
          const [Cell(5, 5), Cell(6, 6), Cell(7, 7), Cell(8, 8)],
        );
        final diagonalResult = await GomokuAi().search(diagonal, level: level);
        expect(diagonalResult!.cell, const Cell(9, 9));
      },
    );
  }

  test('beginner varies legal choices and may overlook threats', () async {
    final session = position(
      const [Cell(4, 2), Cell(10, 2), Cell(10, 4), Cell(12, 6)],
      const [Cell(4, 3), Cell(4, 4), Cell(4, 5), Cell(4, 6)],
    );
    final before = session.toJson();
    final ai = GomokuAi(random: Random(42));
    final choices = <Cell>{};
    for (var search = 0; search < 12; search++) {
      final result = await ai.search(session, level: GomokuAiLevel.beginner);
      expect(session.inside(result!.cell), isTrue);
      expect(session.pieceAt(result.cell), isNull);
      choices.add(result.cell);
    }
    expect(choices.length, greaterThan(3));
    expect(choices.any((cell) => cell != const Cell(4, 7)), isTrue);
    expect(session.toJson(), before);
  });

  test(
    'node, zero-depth and expired time budgets return legal choices',
    () async {
      final session = GomokuSession()..place(const Cell(7, 7));
      final before = session.toJson();
      for (final nodes in [0, 1, 7, 40]) {
        final result = await GomokuAi().search(
          session,
          maxNodes: nodes,
          maxDepth: 10,
          timeLimit: const Duration(seconds: 5),
        );
        expect(result!.nodes, lessThanOrEqualTo(nodes));
        expect(session.inside(result.cell), isTrue);
        expect(session.pieceAt(result.cell), isNull);
      }
      for (final result in [
        await GomokuAi().search(session, maxDepth: 0),
        await GomokuAi().search(session, timeLimit: Duration.zero),
      ]) {
        expect(result!.nodes, 0);
        expect(result.depth, 0);
        expect(session.pieceAt(result.cell), isNull);
      }
      expect(session.toJson(), before);
    },
  );

  test('a timer can cancel search after it has started', () async {
    final session = position(
      const [Cell(7, 7), Cell(8, 6), Cell(9, 9)],
      const [Cell(8, 8), Cell(7, 6), Cell(6, 9)],
    );
    final before = session.toJson();
    final ai = GomokuAi();
    final pending = ai.search(
      session,
      maxDepth: 20,
      maxNodes: 1000000,
      timeLimit: const Duration(seconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ai.cancel();
    expect(await pending, isNull);
    expect(session.toJson(), before);
  });

  test(
    'a newer search cancels the old one, using independent snapshots',
    () async {
      final session = GomokuSession()..place(const Cell(7, 7));
      final ai = GomokuAi();
      final old = ai.search(session, maxDepth: 20, maxNodes: 1000000);
      session.place(const Cell(7, 8));
      final before = session.toJson();
      final current = ai.search(session, maxDepth: 1);
      expect(await old, isNull);
      final result = await current;
      expect(result, isNotNull);
      expect(session.pieceAt(result!.cell), isNull);
      expect(session.toJson(), before);
    },
  );

  test('finished sessions have no AI move', () async {
    final session = GomokuSession()..resign(Side.black);
    expect(await GomokuAi().search(session), isNull);
  });

  for (final level in GomokuAiLevel.values) {
    for (final stones in <List<Cell>>[
      const [Cell(7, 6), Cell(7, 8), Cell(6, 7), Cell(8, 7)],
      const [Cell(7, 3), Cell(7, 4), Cell(7, 6), Cell(7, 7), Cell(7, 8)],
    ]) {
      test(
        '${level.label} only selects legal Renju points (${stones.length} stones)',
        () async {
          final session = position(stones, [
            for (var index = 0; index < stones.length; index++)
              Cell(0, index * 2),
          ], variant: GomokuVariant.renju);
          final forbidden = stones.length == 4
              ? const Cell(7, 7)
              : const Cell(7, 5);
          expect(session.canPlace(forbidden), isFalse);
          final before = session.toJson();
          final ai = GomokuAi(random: Random(42));
          for (
            var index = 0;
            index < (level == GomokuAiLevel.beginner ? 6 : 1);
            index++
          ) {
            final result = await ai.search(session, level: level, maxDepth: 2);
            expect(result, isNotNull);
            expect(result!.cell, isNot(forbidden));
            expect(session.canPlace(result.cell), isTrue);
            expect(session.toJson(), before);
          }
        },
      );
    }
  }

  for (final level in [GomokuAiLevel.intermediate, GomokuAiLevel.advanced]) {
    test(
      '${level.label} chooses an exact-five win before a standard overline',
      () async {
        final session = position(
          const [
            Cell(7, 3),
            Cell(7, 4),
            Cell(7, 6),
            Cell(7, 7),
            Cell(7, 8),
            Cell(10, 3),
            Cell(10, 4),
            Cell(10, 5),
            Cell(10, 6),
          ],
          const [
            Cell(0, 0),
            Cell(0, 2),
            Cell(0, 4),
            Cell(0, 6),
            Cell(0, 8),
            Cell(2, 0),
            Cell(2, 2),
            Cell(2, 4),
            Cell(2, 6),
          ],
          variant: GomokuVariant.standard,
        );
        final long = session.fork()..place(const Cell(7, 5));
        expect(long.gameOver, isFalse);
        final before = session.toJson();
        final result = await GomokuAi().search(session, level: level);
        expect(const [Cell(10, 2), Cell(10, 7)], contains(result!.cell));
        expect((session.fork()..place(result.cell)).winner, Side.black);
        expect(session.toJson(), before);
      },
    );
  }

  test(
    'Renju recursion respects time, node and cancellation budgets',
    () async {
      final session = position(
        const [Cell(7, 6), Cell(7, 8), Cell(6, 7), Cell(8, 7)],
        const [Cell(0, 0), Cell(0, 2), Cell(0, 4), Cell(0, 6)],
        variant: GomokuVariant.renju,
      );
      final before = session.toJson();
      final watch = Stopwatch()..start();
      final result = await GomokuAi().search(
        session,
        maxDepth: 20,
        maxNodes: 100000,
        timeLimit: const Duration(milliseconds: 30),
      );
      expect(result, isNotNull);
      expect(session.canPlace(result!.cell), isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      final limited = await GomokuAi().search(
        session,
        maxNodes: 3,
        maxDepth: 20,
      );
      expect(limited!.nodes, lessThanOrEqualTo(3));
      expect(session.canPlace(limited.cell), isTrue);
      final ai = GomokuAi();
      final pending = ai.search(
        session,
        maxNodes: 100000,
        maxDepth: 20,
        timeLimit: const Duration(seconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      ai.cancel();
      expect(await pending, isNull);
      expect(session.toJson(), before);
    },
  );
}
