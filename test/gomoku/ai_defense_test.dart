import 'dart:math';

import 'package:easyplay/game_session.dart' show Cell;
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:flutter_test/flutter_test.dart';

Cell transform(Cell cell, int symmetry) {
  var row = cell.row, col = cell.col;
  if (symmetry >= 4) col = 14 - col;
  for (var i = 0; i < symmetry % 4; i++) {
    final oldRow = row;
    row = col;
    col = 14 - oldRow;
  }
  return Cell(row, col);
}

GomokuSession position(
  List<Cell> black,
  List<Cell> white,
  GomokuVariant variant,
) {
  final session = GomokuSession(variant: variant);
  for (var i = 0; i < black.length; i++) {
    expect(session.place(black[i]), isTrue);
    if (i < white.length) expect(session.place(white[i]), isTrue);
  }
  return session;
}

void main() {
  for (final level in GomokuAiLevel.values) {
    test(
      '${level.name} takes a win before defending the opponent four',
      () async {
        final session = position(
          const [Cell(7, 3), Cell(7, 4), Cell(7, 5), Cell(7, 6)],
          const [Cell(4, 3), Cell(4, 4), Cell(4, 5), Cell(4, 6)],
          GomokuVariant.freestyle,
        );
        final result = await GomokuAi(
          random: Random(42),
        ).search(session, level: level);
        expect((session.fork()..place(result!.cell)).winner, session.turn);
      },
    );
    test('${level.name} never randomizes away an immediate block', () async {
      final session = position(
        const [Cell(4, 2), Cell(10, 2), Cell(10, 4), Cell(12, 6)],
        const [Cell(4, 3), Cell(4, 4), Cell(4, 5), Cell(4, 6)],
        GomokuVariant.freestyle,
      );
      for (var seed = 0; seed < 4; seed++) {
        final result = await GomokuAi(
          random: Random(seed),
        ).search(session, level: level);
        expect(result!.cell, const Cell(4, 7));
      }
    });
  }

  for (var symmetry = 0; symmetry < 8; symmetry++) {
    test(
      'shallow Renju defense avoids a forbidden reply, symmetry $symmetry',
      () async {
        final session = position(
          const [
            Cell(6, 10),
            Cell(8, 10),
            Cell(6, 9),
            Cell(8, 11),
          ].map((c) => transform(c, symmetry)).toList(),
          const [
            Cell(7, 6),
            Cell(7, 7),
            Cell(7, 8),
            Cell(0, 0),
          ].map((c) => transform(c, symmetry)).toList(),
          GomokuVariant.renju,
        );
        expect(
          session.canPlace(transform(const Cell(7, 10), symmetry)),
          isFalse,
        );
        final losingDefense = session.fork()
          ..place(transform(const Cell(7, 5), symmetry));
        expect(
          losingDefense.place(transform(const Cell(7, 9), symmetry)),
          isTrue,
        );
        expect(
          losingDefense.canPlace(transform(const Cell(7, 10), symmetry)),
          isFalse,
        );
        final before = session.toJson();
        final result = await GomokuAi().search(
          session,
          level: GomokuAiLevel.advanced,
          maxDepth: 1,
          maxNodes: 1000,
          timeLimit: const Duration(seconds: 3),
        );
        expect(result!.cell, transform(const Cell(7, 9), symmetry));
        expect(session.toJson(), before);
      },
    );
  }

  for (final variant in GomokuVariant.values) {
    test(
      '${variant.name} defends a four-three combination beyond the horizon',
      () async {
        final session = position(
          const [Cell(7, 3), Cell(0, 0), Cell(0, 2), Cell(2, 0), Cell(2, 2)],
          const [Cell(7, 4), Cell(7, 5), Cell(7, 6), Cell(5, 7), Cell(6, 7)],
          variant,
        );
        final result = await GomokuAi().search(
          session,
          maxDepth: 1,
          maxNodes: 2000,
          timeLimit: const Duration(seconds: 3),
        );
        expect(const [
          Cell(7, 7),
          Cell(7, 8),
          Cell(4, 7),
          Cell(8, 7),
        ], contains(result!.cell));
      },
    );

    test(
      '${variant.name} searches a forcing four-three to a winning open four',
      () async {
        final session = position(
          const [Cell(7, 4), Cell(7, 5), Cell(7, 6), Cell(5, 7), Cell(6, 7)],
          const [Cell(7, 3), Cell(0, 0), Cell(0, 2), Cell(2, 0), Cell(2, 2)],
          variant,
        );
        final result = await GomokuAi().search(
          session,
          maxDepth: 1,
          maxNodes: 2000,
          timeLimit: const Duration(seconds: 3),
        );
        expect(result!.cell, const Cell(7, 7));
        final continuation = session.fork()..place(result.cell);
        // White must answer the closed four. Black can then create two wins.
        expect(continuation.place(const Cell(7, 8)), isTrue);
        final reply = await GomokuAi().search(continuation, maxDepth: 1);
        expect(const [Cell(4, 7), Cell(8, 7)], contains(reply!.cell));
      },
    );

    test(
      '${variant.name} prevents an open four at a shallow horizon',
      () async {
        final session = position(
          const [Cell(3, 3), Cell(4, 5), Cell(10, 10)],
          const [Cell(7, 6), Cell(7, 7), Cell(7, 8)],
          variant,
        );
        final result = await GomokuAi().search(
          session,
          maxDepth: 1,
          maxNodes: 1000,
          timeLimit: const Duration(seconds: 3),
        );
        expect(const [Cell(7, 5), Cell(7, 9)], contains(result!.cell));
        expect(session.canPlace(result.cell), isTrue);
      },
    );
  }

  test(
    'standard overline is not a forced block; freestyle overline is',
    () async {
      for (final variant in [GomokuVariant.standard, GomokuVariant.freestyle]) {
        final session = position(
          const [Cell(10, 3), Cell(10, 4), Cell(10, 5), Cell(1, 1), Cell(1, 3)],
          const [Cell(7, 3), Cell(7, 4), Cell(7, 6), Cell(7, 7), Cell(7, 8)],
          variant,
        );
        final result = await GomokuAi().search(session, maxDepth: 1);
        expect(
          variant == GomokuVariant.standard
              ? const [Cell(10, 2), Cell(10, 6)].contains(result!.cell)
              : result!.cell == const Cell(7, 5),
          isTrue,
        );
      }
    },
  );
}
