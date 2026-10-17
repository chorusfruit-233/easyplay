import 'dart:math';
import 'dart:async';

import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:flutter_test/flutter_test.dart';

class OpeningAnalysisAi extends GomokuAi {
  OpeningAnalysisAi(this.evaluate);
  final int Function(GomokuSession) evaluate;
  final positions = <GomokuSession>[];

  @override
  Future<GomokuAiResult?> search(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
    int? maxNodes,
    int? maxDepth,
    Duration? timeLimit,
  }) async {
    positions.add(source.fork());
    return GomokuAiResult(const Cell(9, 9), 1, 1, evaluation: evaluate(source));
  }
}

class DelayedOpeningAi extends GomokuAi {
  final pending = Completer<GomokuAiResult?>();
  @override
  Future<GomokuAiResult?> search(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
    int? maxNodes,
    int? maxDepth,
    Duration? timeLimit,
  }) => pending.future;
}

GomokuSession opening() => GomokuSession()
  ..place(const Cell(7, 7))
  ..place(const Cell(6, 7))
  ..place(const Cell(6, 6));

GomokuSession sevenEmptyPoints() {
  final session = GomokuSession();
  for (final cell in const [Cell(7, 7), Cell(6, 6), Cell(5, 6)]) {
    expect(session.place(cell), isTrue);
  }
  expect(session.exchangeColors(false), isTrue);
  for (final cell in const [
    Cell(8, 7),
    Cell(6, 5),
    Cell(8, 6),
    Cell(6, 5),
    Cell(7, 6),
  ]) {
    expect(session.place(cell), isTrue);
  }
  final black = <Cell>[], white = <Cell>[];
  for (var row = 0; row < 15; row++) {
    for (var col = 0; col < 15; col++) {
      final cell = Cell(row, col);
      if (session.pieceAt(cell) != null) continue;
      // Every line has alternating colours or runs of two, so completing this
      // board cannot form five. It is also legal under competitive black rules.
      ((row + 2 * col) % 4 < 2 ? black : white).add(cell);
    }
  }
  black.removeRange(0, 4);
  white.removeRange(0, 3);
  expect(black.length, white.length);
  for (var i = 0; i < black.length; i++) {
    expect(session.place(black[i]), isTrue);
    expect(session.place(white[i]), isTrue);
  }
  return session;
}

void main() {
  test('advanced exchange uses the white-to-move search evaluation', () async {
    for (final score in [-10000000, 10000000]) {
      final session = opening();
      final before = session.toJson();
      final ai = OpeningAnalysisAi((_) => score);
      final action = await ai.decide(session, level: GomokuAiLevel.advanced);
      expect(ai.positions.single.turn, Side.white);
      expect(action!.type, GomokuActionType.exchange);
      expect(action.exchange, score < 0);
      expect(session.toJson(), before);
    }
  });

  test(
    'advanced does not choose colours from an unproven free-fifth estimate',
    () async {
      final session = opening();
      final ai = OpeningAnalysisAi((_) => 50);
      final action = await ai.decide(session, level: GomokuAiLevel.advanced);
      expect(action!.exchange, isTrue);
      expect(session.phase, GomokuPhase.exchange);
    },
  );

  test(
    'advanced selects black five by the resulting white-six position',
    () async {
      final session = opening()
        ..exchangeColors(false)
        ..place(const Cell(8, 8))
        ..place(const Cell(8, 7))
        ..place(const Cell(7, 8));
      final before = session.toJson();
      final ai = OpeningAnalysisAi(
        (position) =>
            position.pieceAt(const Cell(7, 8)) == Side.black ? 100 : -100,
      );
      final action = await ai.decide(session, level: GomokuAiLevel.advanced);
      expect(action!.cell, const Cell(7, 8));
      expect(ai.positions.length, 2);
      for (final candidate in ai.positions) {
        expect(candidate.moves.length, 5);
        expect(candidate.turn, Side.white);
        expect(candidate.phase, GomokuPhase.normal);
      }
      expect(session.toJson(), before);
    },
  );

  test(
    'advanced proposal search excludes the first candidate and its symmetries',
    () async {
      final session = opening()
        ..exchangeColors(false)
        ..place(const Cell(8, 8));
      for (var proposal = 0; proposal < 2; proposal++) {
        final before = session.toJson();
        final result = await GomokuAi(random: Random(42)).search(
          session,
          level: GomokuAiLevel.advanced,
          maxDepth: 1,
          maxNodes: 1000,
          timeLimit: const Duration(seconds: 5),
        );
        expect(session.toJson(), before);
        expect(session.canPlace(result!.cell), isTrue);
        expect(session.place(result.cell), isTrue);
      }
      expect(session.moves.length, 4);
      expect(session.proposals.length, 2);
      expect(session.phase, GomokuPhase.selection);
    },
  );

  test(
    'cancelled opening analysis cannot return a late exchange decision',
    () async {
      final session = opening();
      final before = session.toJson();
      final ai = DelayedOpeningAi();
      final decision = ai.decide(session, level: GomokuAiLevel.advanced);
      await Future<void>.delayed(Duration.zero);
      ai.cancel();
      ai.pending.complete(
        const GomokuAiResult(Cell(9, 9), 1, 1, evaluation: 100),
      );
      expect(await decision, isNull);
      expect(session.toJson(), before);
    },
  );

  test(
    'advanced completes a seven-ply competitive endgame within 4000 nodes',
    () async {
      final session = sevenEmptyPoints();
      final before = session.toJson();
      final result = await GomokuAi(random: Random(42)).search(
        session,
        level: GomokuAiLevel.advanced,
        maxNodes: 4000,
        timeLimit: const Duration(seconds: 5),
      );
      expect(result, isNotNull);
      // The previous advanced ceiling stopped after five plies (999 nodes).
      expect(result!.depth, 7);
      expect(result.evaluation, 0);
      expect(result.nodes, lessThanOrEqualTo(4000));
      expect(session.canPlace(result.cell), isTrue);
      expect(session.toJson(), before);
      final finish = session.fork()..place(result.cell);
      while (!finish.gameOver) {
        final empty = [
          for (var row = 0; row < 15; row++)
            for (var col = 0; col < 15; col++)
              if (finish.canPlace(Cell(row, col))) Cell(row, col),
        ];
        expect(empty, isNotEmpty);
        expect(finish.place(empty.first), isTrue);
      }
      expect(finish.moves.length, 225);
      expect(finish.winner, isNull);
    },
  );

  test(
    'advanced principal-variation search can be cancelled without changing the board',
    () async {
      final session = GomokuSession()..place(const Cell(7, 7));
      final before = session.toJson();
      final ai = GomokuAi();
      final pending = ai.search(
        session,
        level: GomokuAiLevel.advanced,
        maxDepth: 20,
        maxNodes: 100000,
        timeLimit: const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      ai.cancel();
      expect(await pending, isNull);
      expect(session.toJson(), before);
    },
  );
}
