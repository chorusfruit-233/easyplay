import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:flutter_test/flutter_test.dart';

GomokuSession blackPosition(
  List<Cell> cells, {
  GomokuVariant variant = GomokuVariant.freestyle,
}) {
  final session = GomokuSession(variant: variant);
  const fillers = [Cell(0, 0), Cell(0, 2), Cell(0, 4), Cell(0, 6), Cell(0, 8)];
  for (var index = 0; index < cells.length; index++) {
    expect(session.place(cells[index]), isTrue);
    if (index + 1 < cells.length) {
      expect(session.place(fillers[index]), isTrue);
    }
  }
  return session;
}

void main() {
  test('black starts; occupied and outside cells leave state unchanged', () {
    final session = GomokuSession();
    expect(session.size, 15);
    expect(session.turn, Side.black);
    expect(session.undo(), isFalse);
    expect(session.place(const Cell(7, 7)), isTrue);
    expect(session.turn, Side.white);
    final before = session.toJson();
    for (final cell in [
      const Cell(7, 7),
      const Cell(-1, 7),
      const Cell(15, 7),
      const Cell(7, 15),
    ]) {
      expect(session.place(cell), isFalse);
      expect(session.toJson(), before);
    }
    expect(session.pieceAt(const Cell(-1, 0)), isNull);
    expect(() => session.board[0][0] = Side.white, throwsUnsupportedError);
    expect(() => session.moves.clear(), throwsUnsupportedError);
  });

  for (final (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)]) {
    test('five wins in direction ($dr, $dc)', () {
      final cells = [
        for (var step = 0; step < 5; step++) Cell(6 + dr * step, 7 + dc * step),
      ];
      final session = blackPosition(cells);
      expect(session.gameOver, isTrue);
      expect(session.winner, Side.black);
      expect(session.winningLine, cells);
      expect(session.resigned, isFalse);
      expect(session.place(const Cell(14, 14)), isFalse);
      expect(session.resign(Side.black), isFalse);
      expect(session.undo(), isTrue);
      expect(session.gameOver, isFalse);
      expect(session.winner, isNull);
      expect(session.winningLine, isEmpty);
      expect(session.turn, Side.black);
      expect(session.place(cells.last), isTrue);
      expect(session.winner, Side.black);
    });
  }

  test('long lines win when the last stone fills a gap', () {
    final session = blackPosition(const [
      Cell(7, 3),
      Cell(7, 4),
      Cell(7, 6),
      Cell(7, 7),
      Cell(7, 8),
      Cell(7, 5),
    ]);
    expect(session.winner, Side.black);
    expect(session.winningLine.length, 6);
  });

  test('white can win; opposite edges do not wrap into a line', () {
    final session = GomokuSession();
    for (var step = 0; step < 5; step++) {
      expect(session.place(Cell(0, step * 2)), isTrue);
      expect(session.place(Cell(14, 10 + step)), isTrue);
    }
    expect(session.winner, Side.white);
    final edges = blackPosition(const [
      Cell(5, 13),
      Cell(5, 14),
      Cell(6, 0),
      Cell(6, 1),
      Cell(6, 2),
    ]);
    expect(edges.gameOver, isFalse);
  });

  test('full board with no line is a draw', () {
    final black = <Cell>[];
    final white = <Cell>[];
    for (var row = 0; row < 15; row++) {
      for (var col = 0; col < 15; col++) {
        ((row + 2 * col) % 4 < 2 ? black : white).add(Cell(row, col));
      }
    }
    expect(black.length, 113);
    final session = GomokuSession();
    for (var index = 0; index < black.length; index++) {
      expect(session.place(black[index]), isTrue);
      if (index < white.length) expect(session.place(white[index]), isTrue);
    }
    expect(session.gameOver, isTrue);
    expect(session.winner, isNull);
    expect(session.resultLabel, '和棋');
    expect(session.winningLine, isEmpty);
    expect(session.undo(), isTrue);
    expect(session.gameOver, isFalse);
    expect(session.place(black.last), isTrue);
    expect(session.gameOver, isTrue);
  });

  test('resignation, undo, independent fork and reset', () {
    final session = GomokuSession()..place(const Cell(7, 7));
    final copy = session.fork();
    expect(copy.toJson(), session.toJson());
    expect(copy.resign(Side.black), isTrue);
    expect(copy.winner, Side.white);
    expect(copy.resigned, isTrue);
    expect(copy.undo(), isTrue);
    expect(copy.moves.length, 1);
    expect(copy.turn, Side.white);
    expect(copy.place(const Cell(6, 6)), isTrue);
    expect(session.pieceAt(const Cell(6, 6)), isNull);
    final revision = copy.revision;
    copy.reset();
    expect(copy.moves, isEmpty);
    expect(copy.turn, Side.black);
    expect(copy.gameOver, isFalse);
    expect(copy.revision, greaterThan(revision));
    expect(session.moves.length, 1);
  });

  test('JSON round trips live, undone, reset, won and resigned records', () {
    final session = GomokuSession()..place(const Cell(7, 7));
    void roundTrip(GomokuSession value) {
      final restored = GomokuSession.fromJson(value.toJson());
      expect(restored.toJson(), value.toJson());
      expect(restored.board, value.board);
      expect(restored.winningLine, value.winningLine);
    }

    roundTrip(session);
    session.place(const Cell(6, 6));
    session.undo();
    roundTrip(session);
    session.resign(Side.white);
    roundTrip(session);
    session.reset();
    roundTrip(session);
    roundTrip(
      blackPosition(const [
        Cell(6, 6),
        Cell(6, 7),
        Cell(6, 8),
        Cell(6, 9),
        Cell(6, 10),
      ]),
    );
  });

  test('JSON rejects forged metadata and illegal replay', () {
    final valid = (GomokuSession()..place(const Cell(7, 7))).toJson();
    final bad = <Object?>[
      null,
      {},
      {...valid, 'size': 19},
      {...valid, 'size': 15.0},
      {...valid, 'version': 3},
      {...valid, 'version': 2.0},
      {...valid, 'turn': 'black'},
      {...valid, 'winner': 'black'},
      {...valid, 'gameOver': true},
      {...valid, 'revision': 0},
      {...valid, 'revision': 1.5},
      {...valid, 'resignedSide': 'white'},
      {...valid, 'resigned': true},
      {
        ...valid,
        'moves': [
          {'row': 7, 'col': 7, 'side': 'white'},
        ],
      },
      {
        ...valid,
        'moves': [
          {'row': 7, 'col': 15, 'side': 'black'},
        ],
      },
      {
        ...valid,
        'moves': [
          {'row': 7, 'col': 7.0, 'side': 'black'},
        ],
      },
      {
        ...valid,
        'moves': [
          {'row': 7, 'col': 7, 'side': 'black'},
          {'row': 7, 'col': 7, 'side': 'white'},
        ],
      },
    ];
    for (final record in bad) {
      expect(() => GomokuSession.fromJson(record), throwsFormatException);
    }
    final won = blackPosition(const [
      Cell(6, 6),
      Cell(6, 7),
      Cell(6, 8),
      Cell(6, 9),
      Cell(6, 10),
    ]).toJson();
    expect(
      () => GomokuSession.fromJson({
        ...won,
        'moves': [
          ...won['moves'] as List,
          {'row': 14, 'col': 14, 'side': 'white'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('standard long lines stay live for both sides', () {
    final session = blackPosition(const [
      Cell(7, 3),
      Cell(7, 4),
      Cell(7, 6),
      Cell(7, 7),
      Cell(7, 8),
      Cell(7, 5),
    ], variant: GomokuVariant.standard);
    expect(session.gameOver, isFalse);
    expect(session.winningLine, isEmpty);
    expect(session.variant, GomokuVariant.standard);
    final white = GomokuSession(variant: GomokuVariant.standard);
    const cols = [3, 4, 6, 7, 8, 5];
    for (var index = 0; index < cols.length; index++) {
      expect(white.place(Cell(0, index * 2)), isTrue);
      expect(white.place(Cell(7, cols[index])), isTrue);
    }
    expect(white.gameOver, isFalse);
    expect(white.winningLine, isEmpty);
  });

  test('Renju forbidden rejection preserves every part of session state', () {
    final session = blackPosition(const [
      Cell(7, 6),
      Cell(7, 8),
      Cell(6, 7),
      Cell(8, 7),
    ], variant: GomokuVariant.renju)..place(const Cell(0, 6));
    final before = session.toJson();
    expect(session.turn, Side.black);
    expect(session.canPlace(const Cell(7, 7)), isFalse);
    expect(session.rejectionReason(const Cell(7, 7)), '双活三禁手');
    expect(session.place(const Cell(7, 7)), isFalse);
    expect(session.toJson(), before);
    expect(session.gameOver, isFalse);
    expect(session.canPlace(const Cell(14, 14)), isTrue);
    expect(session.place(const Cell(14, 14)), isTrue);
    expect(session.rejectionReason(const Cell(14, 14)), '该位置已有棋子');
  });

  test('variant survives undo, fork, reset and serialized restore', () {
    for (final variant in GomokuVariant.values) {
      final session = GomokuSession(variant: variant);
      session.place(const Cell(7, 7));
      session.place(const Cell(8, 8));
      session.undo();
      expect(session.variant, variant);
      final copy = session.fork();
      expect(copy.variant, variant);
      expect(copy.toJson(), session.toJson());
      expect(GomokuSession.fromJson(copy.toJson()).variant, variant);
      copy.reset();
      expect(copy.variant, variant);
      expect(copy.moves, isEmpty);
      expect(session.moves.length, 1);
    }
  });

  test(
    'version 1 migrates only to freestyle; version 2 requires known variant',
    () {
      final valid = (GomokuSession()..place(const Cell(7, 7))).toJson();
      final legacy = {...valid, 'version': 1}..remove('variant');
      final restored = GomokuSession.fromJson(legacy);
      expect(restored.variant, GomokuVariant.freestyle);
      expect(restored.toJson()['version'], 2);
      expect(restored.moves.length, 1);
      final missing = {...valid}..remove('variant');
      for (final record in [
        missing,
        {...valid, 'variant': 'unknown'},
        {...valid, 'variant': null},
        {...valid, 'variant': 1},
        {...legacy, 'variant': 'freestyle'},
        {...legacy, 'variant': 'renju'},
      ]) {
        expect(() => GomokuSession.fromJson(record), throwsFormatException);
      }
      expect(GomokuVariant.fromName('standard'), GomokuVariant.standard);
      expect(() => GomokuVariant.fromName('Standard'), throwsFormatException);
    },
  );

  test(
    'JSON replay rejects a forbidden black move and forged result metadata',
    () {
      final session = blackPosition(const [
        Cell(7, 6),
        Cell(7, 8),
        Cell(6, 7),
        Cell(8, 7),
      ])..place(const Cell(0, 6));
      session.place(const Cell(7, 7));
      expect(
        () => GomokuSession.fromJson({...session.toJson(), 'variant': 'renju'}),
        throwsFormatException,
      );
      final long = blackPosition(const [
        Cell(7, 3),
        Cell(7, 4),
        Cell(7, 6),
        Cell(7, 7),
        Cell(7, 8),
        Cell(7, 5),
      ]);
      expect(
        () => GomokuSession.fromJson({...long.toJson(), 'variant': 'standard'}),
        throwsFormatException,
      );
      expect(
        () => GomokuSession.fromJson({...long.toJson(), 'variant': 'renju'}),
        throwsFormatException,
      );
    },
  );
}
