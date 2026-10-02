import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/game_session.dart' show Cell, Side;

DraughtsPosition board(Map<Cell, DraughtsPiece> pieces) {
  final cells = List<DraughtsPiece?>.filled(64, null);
  for (final entry in pieces.entries) {
    cells[entry.key.row * 8 + entry.key.col] = entry.value;
  }
  return DraughtsPosition(8, cells);
}

void main() {
  test('beginner overlooks an immediate loss that intermediate avoids', () async {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
      position: board({
        const Cell(2, 3): const DraughtsPiece(Side.black),
        const Cell(4, 5): const DraughtsPiece(Side.white),
      }),
    );
    // Exercise the non-random branch: a one-ply beginner cannot resolve the
    // opponent's capture, even when it has enough time for the whole iteration.
    final beginner = await DraughtsAi(random: _SearchOnlyRandom()).search(
      session,
      level: DraughtsAiLevel.beginner,
      timeLimit: const Duration(seconds: 5),
    );
    expect(beginner!.depth, 1);
    expect(beginner.nodes, lessThanOrEqualTo(DraughtsAiLevel.beginner.nodes));
    expect(beginner.move.to, const Cell(3, 4));
    final intermediate = await DraughtsAi().search(
      session,
      timeLimit: const Duration(seconds: 5),
    );
    expect(intermediate!.move.to, const Cell(3, 2));
    final continuation = session.fork()..applyMove(beginner.move);
    continuation.applyMove(continuation.legalMoves().single);
    expect(continuation.result!.winner, Side.white);
    expect(session.moves, isEmpty);
  });

  test(
    'beginner randomizes legal choices instead of always optimizing',
    () async {
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.english),
      );
      final before = session.toJson();
      final ai = DraughtsAi(random: Random(42));
      final chosen = <DraughtsMove>{};
      for (var i = 0; i < 30; i++) {
        final result = await ai.search(
          session,
          level: DraughtsAiLevel.beginner,
          timeLimit: const Duration(seconds: 5),
        );
        expect(session.legalMoves(), contains(result!.move));
        chosen.add(result.move);
      }
      expect(chosen.length, greaterThan(3));
      expect(session.toJson(), before);
    },
  );

  test(
    'beginner random choices retain maximum complete capture paths',
    () async {
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.brazilian),
        position: board({
          const Cell(0, 1): const DraughtsPiece(Side.black),
          const Cell(2, 7): const DraughtsPiece(Side.black),
          const Cell(1, 2): const DraughtsPiece(Side.white),
          const Cell(3, 4): const DraughtsPiece(Side.white),
          const Cell(3, 6): const DraughtsPiece(Side.white),
          const Cell(5, 6): const DraughtsPiece(Side.white),
        }),
        turn: Side.black,
      );
      for (var seed = 0; seed < 8; seed++) {
        final result = await DraughtsAi(
          random: Random(seed),
        ).search(session, level: DraughtsAiLevel.beginner);
        expect(session.legalMoves(), contains(result!.move));
        expect(result.move.captures.length, 3);
        expect(result.move.path.length, 4);
        final fork = session.fork();
        expect(fork.applyMove(result.move), isTrue);
        expect(fork.moveCount, 1);
      }
      expect(session.moves, isEmpty);
    },
  );

  for (final variant in DraughtsVariant.values) {
    test(
      'AI returns legal moves without changing $variant live state',
      () async {
        final session = DraughtsSession(DraughtsRules.forVariant(variant));
        session.applyMove(session.legalMoves().first);
        final before = session.toJson();
        final revision = session.revision;
        final result = await DraughtsAi().search(
          session,
          maxDepth: 2,
          maxNodes: 120,
          timeLimit: const Duration(seconds: 5),
        );
        expect(session.legalMoves(), contains(result!.move));
        expect(result.nodes, lessThanOrEqualTo(120));
        expect(session.toJson(), before);
        expect(session.revision, revision);
        final beginner = await DraughtsAi(random: Random(42)).search(
          session,
          level: DraughtsAiLevel.beginner,
          timeLimit: const Duration(seconds: 5),
        );
        expect(session.legalMoves(), contains(beginner!.move));
        expect(beginner.depth, lessThanOrEqualTo(1));
        expect(
          beginner.nodes,
          lessThanOrEqualTo(DraughtsAiLevel.beginner.nodes),
        );
        expect(session.toJson(), before);
        expect(session.revision, revision);
        expect(session.undo(), isTrue);
        expect(session.moves, isEmpty);
      },
    );
  }

  test('AI submits a winning triple capture as one atomic move', () async {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
      position: board({
        const Cell(0, 1): const DraughtsPiece(Side.black),
        const Cell(1, 2): const DraughtsPiece(Side.white),
        const Cell(3, 4): const DraughtsPiece(Side.white),
        const Cell(5, 6): const DraughtsPiece(Side.white),
      }),
    );
    final result = await DraughtsAi().search(session);
    expect(result!.move.captures.length, 3);
    expect(session.moves, isEmpty);
    expect(session.applyMove(result.move), isTrue);
    expect(session.moves.length, 1);
    expect(session.result!.winner, Side.black);
    expect(session.undo(), isTrue);
    expect(session.position.count(Side.white), 3);
  });

  test('two-ply search avoids a free capture by the opponent', () async {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
      position: board({
        const Cell(2, 3): const DraughtsPiece(Side.black),
        const Cell(4, 5): const DraughtsPiece(Side.white),
      }),
    );
    final result = await DraughtsAi().search(
      session,
      maxDepth: 2,
      maxNodes: 2000,
      timeLimit: const Duration(seconds: 5),
    );
    expect(result!.move.to, const Cell(3, 2));
    expect(result.depth, 2);
  });

  test(
    'budget exhaustion retains a legal fallback and never exceeds nodes',
    () async {
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.international),
      );
      final result = await DraughtsAi().search(session, maxNodes: 0);
      expect(result!.depth, 0);
      expect(result.nodes, 0);
      expect(session.legalMoves(), contains(result.move));
    },
  );

  test('cancelled and superseded searches cannot return stale moves', () async {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
    );
    final ai = DraughtsAi();
    final cancelled = ai.search(session);
    ai.cancel();
    expect(await cancelled, isNull);
    final old = ai.search(session);
    final latest = ai.search(session, maxNodes: 30);
    expect(await old, isNull);
    expect(await latest, isNotNull);
    final beginner = ai.search(session, level: DraughtsAiLevel.beginner);
    ai.cancel();
    expect(await beginner, isNull);
  });

  test('finished games produce no AI move', () async {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
    );
    session.resign();
    expect(await DraughtsAi().search(session), isNull);
  });

  test('search fork retains repetition and quiet draw history', () {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
      position: board({
        const Cell(2, 1): const DraughtsPiece(Side.black, DraughtsRank.king),
        const Cell(5, 6): const DraughtsPiece(Side.white, DraughtsRank.king),
      }),
    );
    final cycle = [
      (const Cell(2, 1), const Cell(3, 0)),
      (const Cell(5, 6), const Cell(4, 7)),
      (const Cell(3, 0), const Cell(2, 1)),
      (const Cell(4, 7), const Cell(5, 6)),
    ];
    for (var i = 0; i < 7; i++) {
      final (from, to) = cycle[i % 4];
      session.applyMove(
        session.legalMoves().firstWhere((m) => m.from == from && m.to == to),
      );
    }
    final fork = session.fork();
    final (from, to) = cycle.last;
    fork.applyMove(
      fork.legalMoves().firstWhere((m) => m.from == from && m.to == to),
    );
    expect(fork.result!.reason, DraughtsEndReason.drawRule);
    expect(session.gameOver, isFalse);
    expect(fork.undo(), isTrue);
    expect(fork.quietPlies, session.quietPlies);
    expect(fork.position, same(session.position));
  });
}

class _SearchOnlyRandom implements Random {
  @override
  double nextDouble() => 0.99;
  @override
  int nextInt(int max) => throw StateError('Search branch must not randomize');
  @override
  bool nextBool() => throw StateError('Not used');
}
