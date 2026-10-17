import 'dart:math';

import 'package:easyplay/game_session.dart' show Cell;
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:flutter_test/flutter_test.dart';

String openingShape(GomokuSession session) {
  final shapes = <String>[];
  for (var symmetry = 0; symmetry < 8; symmetry++) {
    shapes.add(
      session.moves
          .map((move) {
            var row = move.cell.row - 7, col = move.cell.col - 7;
            if (symmetry >= 4) col = -col;
            for (var turn = 0; turn < symmetry % 4; turn++) {
              (row, col) = (-col, row);
            }
            return '$row,$col';
          })
          .join(';'),
    );
  }
  shapes.sort();
  return shapes.first;
}

void main() {
  test(
    'new games vary opening shapes beyond rotations and reflections',
    () async {
      final ai = GomokuAi(random: Random(42));
      final shapes = <String>{};
      for (var game = 0; game < 96; game++) {
        final session = GomokuSession();
        for (var move = 0; move < 3; move++) {
          final before = session.toJson();
          final action = await ai.decide(session);
          expect(session.toJson(), before);
          expect(action, isNotNull);
          expect(session.applyAction(action!), isTrue);
        }
        expect(session.moves.first.cell, const Cell(7, 7));
        expect(session.phase, GomokuPhase.exchange);
        shapes.add(openingShape(session));
      }
      expect(shapes.length, greaterThan(13));
    },
  );

  for (final level in [GomokuAiLevel.intermediate, GomokuAiLevel.advanced]) {
    test('${level.label} varies equally scored quiet moves', () async {
      final session = GomokuSession(variant: GomokuVariant.freestyle)
        ..place(const Cell(7, 7));
      final before = session.toJson();
      final ai = GomokuAi(random: Random(42));
      final choices = <Cell>{};
      for (var attempt = 0; attempt < 16; attempt++) {
        final result = await ai.search(
          session,
          level: level,
          maxDepth: 1,
          maxNodes: 1000,
          timeLimit: const Duration(seconds: 5),
        );
        expect(result, isNotNull);
        expect(result!.depth, 1);
        expect(session.canPlace(result.cell), isTrue);
        choices.add(result.cell);
      }
      expect(choices.length, greaterThan(1));
      expect(session.toJson(), before);
    });
  }

  test('seeded opening decisions remain reproducible after resume', () async {
    final left = GomokuAi(random: Random(17));
    final right = GomokuAi(random: Random(17));
    for (var game = 0; game < 8; game++) {
      final session = GomokuSession();
      for (var move = 0; move < 3; move++) {
        final action = await left.decide(session);
        final restored = GomokuSession.fromJson(session.toJson());
        final repeated = await right.decide(restored);
        expect(repeated!.toJson(), action!.toJson());
        expect(session.applyAction(action), isTrue);
      }
    }
  });

  for (final level in GomokuAiLevel.values) {
    test(
      '${level.label} never varies away from the only immediate block',
      () async {
        final session = GomokuSession(variant: GomokuVariant.freestyle);
        for (final (black, white) in const [
          (Cell(4, 2), Cell(4, 3)),
          (Cell(10, 2), Cell(4, 4)),
          (Cell(10, 4), Cell(4, 5)),
          (Cell(12, 6), Cell(4, 6)),
        ]) {
          session.place(black);
          session.place(white);
        }
        final before = session.toJson();
        for (var seed = 0; seed < 8; seed++) {
          final result = await GomokuAi(
            random: Random(seed),
          ).search(session, level: level);
          expect(result!.cell, const Cell(4, 7));
        }
        expect(session.toJson(), before);
      },
    );
  }
}
