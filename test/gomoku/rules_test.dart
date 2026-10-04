import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_rules.dart';
import 'package:easyplay/gomoku/gomoku_variant.dart';
import 'package:flutter_test/flutter_test.dart';

List<Side?> board(List<Cell> black, [List<Cell> white = const []]) {
  final result = List<Side?>.filled(225, null);
  for (final cell in black) {
    result[cell.row * 15 + cell.col] = Side.black;
  }
  for (final cell in white) {
    result[cell.row * 15 + cell.col] = Side.white;
  }
  return result;
}

GomokuMoveAnalysis renju(List<Side?> cells, [Cell cell = const Cell(7, 7)]) =>
    analyzeGomokuMove(cells, cell, Side.black, variant: GomokuVariant.renju);

void main() {
  test('analysis rejects occupied/outside points without mutating input', () {
    final cells = board(const [Cell(7, 7)]);
    final before = List.of(cells);
    expect(renju(cells).legal, isFalse);
    expect(renju(cells, const Cell(-1, 7)).legal, isFalse);
    expect(cells, before);
    expect(
      () => analyzeGomokuMove([], const Cell(7, 7), Side.black),
      throwsArgumentError,
    );
  });

  test(
    'budget interruption cannot change the caller board during recursion',
    () {
      final cells = board(const [
        Cell(7, 6),
        Cell(7, 8),
        Cell(6, 7),
        Cell(8, 7),
      ]);
      final before = List.of(cells);
      var calls = 0;
      expect(
        () => analyzeGomokuMove(
          cells,
          const Cell(7, 7),
          Side.black,
          variant: GomokuVariant.renju,
          checkBudget: () {
            if (++calls >= 55) throw StateError('budget exhausted');
          },
        ),
        throwsStateError,
      );
      expect(cells, before);
    },
  );

  for (final side in Side.values) {
    for (final (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)]) {
      test('standard exact five for ${side.name}, direction $dr/$dc', () {
        final cells = List<Side?>.filled(225, null);
        for (final step in [-2, -1, 1, 2]) {
          cells[(7 + dr * step) * 15 + 7 + dc * step] = side;
        }
        final result = analyzeGomokuMove(
          cells,
          const Cell(7, 7),
          side,
          variant: GomokuVariant.standard,
        );
        expect(result.legal, isTrue);
        expect(result.winningLine.length, 5);
        cells[(7 + dr * 3) * 15 + 7 + dc * 3] = side;
        final long = analyzeGomokuMove(
          cells,
          const Cell(7, 7),
          side,
          variant: GomokuVariant.standard,
        );
        expect(long.legal, isTrue);
        expect(long.winningLine, isEmpty);
      });
    }
  }

  test('Renju overlines are forbidden for black and a win for white', () {
    const stones = [Cell(7, 3), Cell(7, 4), Cell(7, 6), Cell(7, 7), Cell(7, 8)];
    final black = renju(board(stones), const Cell(7, 5));
    expect(black.forbidden, GomokuForbidden.overline);
    expect(black.legal, isFalse);
    final white = analyzeGomokuMove(
      board([], stones),
      const Cell(7, 5),
      Side.white,
      variant: GomokuVariant.renju,
    );
    expect(white.legal, isTrue);
    expect(white.winningLine.length, 6);
  });

  test('one open four is counted once despite its two winning ends', () {
    final result = renju(board(const [Cell(7, 5), Cell(7, 6), Cell(7, 8)]));
    expect(result.legal, isTrue);
    expect(result.forbidden, isNull);
  });

  test('distinct fours on the same line are a double-four', () {
    // ...X.XXP.X..... has different four-stone sets {3,5,6,7} and
    // {5,6,7,9}; their exact-five continuations are columns 4 and 8.
    final result = renju(
      board(const [Cell(7, 3), Cell(7, 5), Cell(7, 6), Cell(7, 9)]),
    );
    expect(result.forbidden, GomokuForbidden.doubleFour);
    expect(result.legal, isFalse);
  });

  test('crossing fours are forbidden; a four plus one three is legal', () {
    final result = renju(
      board(const [
        Cell(7, 4),
        Cell(7, 5),
        Cell(7, 6),
        Cell(4, 7),
        Cell(5, 7),
        Cell(6, 7),
      ]),
    );
    expect(result.forbidden, GomokuForbidden.doubleFour);
    final fourThree = renju(
      board(const [Cell(7, 4), Cell(7, 5), Cell(7, 6), Cell(6, 7), Cell(8, 7)]),
    );
    expect(fourThree.legal, isTrue);
  });

  test('a supposed four whose winning point makes six is not a four', () {
    final result = renju(
      board(const [
        Cell(7, 2),
        Cell(7, 3),
        Cell(7, 4),
        Cell(7, 6),
        Cell(4, 7),
        Cell(5, 7),
        Cell(6, 7),
      ]),
    );
    expect(result.legal, isTrue);
  });

  test('two true open threes are forbidden only for black', () {
    const stones = [Cell(7, 6), Cell(7, 8), Cell(6, 7), Cell(8, 7)];
    final cells = board(stones);
    final before = List.of(cells);
    final black = renju(cells);
    expect(black.forbidden, GomokuForbidden.doubleThree);
    expect(cells, before);
    final white = analyzeGomokuMove(
      board([], stones),
      const Cell(7, 7),
      Side.white,
      variant: GomokuVariant.renju,
    );
    expect(white.legal, isTrue);
  });

  test('broken open threes and ordinary threes share the same rules', () {
    final result = renju(
      board(const [Cell(7, 5), Cell(7, 8), Cell(6, 7), Cell(8, 7)]),
    );
    expect(result.forbidden, GomokuForbidden.doubleThree);
  });

  test('blocked and edge threes are not open threes', () {
    final blocked = renju(
      board(
        const [Cell(7, 6), Cell(7, 8), Cell(6, 7), Cell(8, 7)],
        const [Cell(7, 5), Cell(7, 9)],
      ),
    );
    expect(blocked.legal, isTrue);
    final edge = renju(
      board(const [Cell(0, 7), Cell(2, 7), Cell(1, 6), Cell(1, 8)]),
      const Cell(1, 7),
    );
    expect(edge.legal, isTrue);
  });

  test('straight fours need two exact-five endpoints, not an overline end', () {
    final result = renju(
      board(const [
        Cell(7, 3),
        Cell(7, 6),
        Cell(7, 8),
        Cell(7, 11),
        Cell(6, 7),
        Cell(8, 7),
      ]),
    );
    expect(result.legal, isTrue);
  });

  for (final cause in ['overline', 'doubleFour', 'five']) {
    test('a three is fake when both extensions cause $cause', () {
      final stones = <Cell>[
        const Cell(7, 6),
        const Cell(7, 8),
        const Cell(6, 7),
        const Cell(8, 7),
        for (final col in [5, 9])
          for (final row in switch (cause) {
            'overline' => [4, 5, 6, 8, 9],
            'doubleFour' => [4, 5, 6],
            _ => [3, 4, 5, 6],
          })
            Cell(row, col),
      ];
      final result = renju(board(stones));
      expect(result.legal, isTrue);
      expect(result.forbidden, isNull);
    });
  }

  test(
    'recursive double-three extensions turn an apparent double-three legal',
    () {
      // P=(7,7) appears to make two open threes. Horizontal extensions B=(7,5)
      // and C=(7,9) each instead make a forbidden double-three of their own.
      // That makes P's horizontal three fake under the recursive RIF 9.3 rule.
      const stones = [
        Cell(7, 6),
        Cell(7, 8),
        Cell(6, 7),
        Cell(8, 7),
        Cell(6, 5),
        Cell(8, 5),
        Cell(6, 4),
        Cell(8, 6),
        Cell(6, 9),
        Cell(8, 9),
        Cell(6, 10),
        Cell(8, 8),
      ];
      for (var transform = 0; transform < 8; transform++) {
        Cell map(Cell cell) {
          var row = cell.row;
          var col = cell.col;
          if (transform >= 4) col = 14 - col;
          for (var turn = 0; turn < transform % 4; turn++) {
            final next = col;
            col = 14 - row;
            row = next;
          }
          return Cell(row, col);
        }

        final cells = board(stones.map(map).toList());
        final root = map(const Cell(7, 7));
        final before = List.of(cells);
        expect(renju(cells, root).legal, isTrue);
        expect(cells, before);
        cells[root.row * 15 + root.col] = Side.black;
        for (final extension in [const Cell(7, 5), const Cell(7, 9)]) {
          expect(
            renju(cells, map(extension)).forbidden,
            GomokuForbidden.doubleThree,
          );
        }
      }
    },
  );

  test('an exact five takes precedence over simultaneous black overline', () {
    final result = renju(
      board(const [
        Cell(7, 3),
        Cell(7, 4),
        Cell(7, 5),
        Cell(7, 6),
        Cell(3, 7),
        Cell(4, 7),
        Cell(5, 7),
        Cell(6, 7),
        Cell(8, 7),
      ]),
    );
    expect(result.legal, isTrue);
    expect(result.forbidden, isNull);
    expect(result.winningLine.length, 5);
  });

  test(
    'two recursive levels can turn a fake extension legal and root forbidden',
    () {
      // P=(7,7), B=(7,5), E=(9,5). E has ONE four at column 5,
      // {6,7,8,9}, but also two real threes: row 9 {4,5,6} can extend
      // legally at (9,3), and diagonal {(7,7),(8,6),(9,5)} at (10,4).
      // Thus E is forbidden double-three. B's column-5 three {6,7,8}
      // cannot extend at (5,5) (White) or at E (forbidden), so it is fake.
      // B's other three {(6,4),(7,5),(8,6)} has legal extension (5,3),
      // hence B is legal. That makes P's horizontal three REAL via B;
      // P's vertical three has legal extension (5,7), so P is forbidden.
      // The assertions below verify each legal extension has two EXACT-five
      // continuations, not just visually plausible three/four shapes.
      const stones = [
        Cell(7, 6),
        Cell(7, 8),
        Cell(6, 7),
        Cell(8, 7),
        Cell(6, 5),
        Cell(8, 5),
        Cell(6, 4),
        Cell(8, 6),
        Cell(6, 9),
        Cell(8, 9),
        Cell(6, 10),
        Cell(8, 8),
        Cell(9, 4),
        Cell(9, 6),
      ];
      final cells = board(stones, const [Cell(5, 5)]);
      const p = Cell(7, 7);
      const b = Cell(7, 5);
      const e = Cell(9, 5);
      expect(renju(cells, p).forbidden, GomokuForbidden.doubleThree);
      cells[p.row * 15 + p.col] = Side.black;
      expect(renju(cells, b).legal, isTrue);

      void verifyStraightFour(
        List<Side?> source,
        Cell extension,
        List<Cell> four,
        List<Cell> endpoints,
      ) {
        final continuation = List<Side?>.of(source);
        final analysis = renju(continuation, extension);
        expect(analysis.legal, isTrue);
        expect(analysis.winningLine, isEmpty);
        continuation[extension.row * 15 + extension.col] = Side.black;
        for (final endpoint in endpoints) {
          final win = renju(continuation, endpoint);
          expect(win.legal, isTrue);
          expect(win.winningLine.length, 5);
          expect(win.winningLine, unorderedEquals([...four, endpoint]));
        }
      }

      verifyStraightFour(
        cells,
        b,
        const [Cell(7, 5), Cell(7, 6), Cell(7, 7), Cell(7, 8)],
        const [Cell(7, 4), Cell(7, 9)],
      );
      verifyStraightFour(
        cells,
        const Cell(5, 7),
        const [Cell(5, 7), Cell(6, 7), Cell(7, 7), Cell(8, 7)],
        const [Cell(4, 7), Cell(9, 7)],
      );
      cells[b.row * 15 + b.col] = Side.black;
      expect(renju(cells, e).forbidden, GomokuForbidden.doubleThree);
      expect(renju(cells, const Cell(5, 5)).legal, isFalse);
      verifyStraightFour(
        cells,
        const Cell(5, 3),
        const [Cell(5, 3), Cell(6, 4), Cell(7, 5), Cell(8, 6)],
        const [Cell(4, 2), Cell(9, 7)],
      );
      // Hypothetically place E only to inspect the threes that make E forbidden.
      cells[e.row * 15 + e.col] = Side.black;
      verifyStraightFour(
        cells,
        const Cell(9, 3),
        const [Cell(9, 3), Cell(9, 4), Cell(9, 5), Cell(9, 6)],
        const [Cell(9, 2), Cell(9, 7)],
      );
      verifyStraightFour(
        cells,
        const Cell(10, 4),
        const [Cell(7, 7), Cell(8, 6), Cell(9, 5), Cell(10, 4)],
        const [Cell(6, 8), Cell(11, 3)],
      );
    },
  );
}
