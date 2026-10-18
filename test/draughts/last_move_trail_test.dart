import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_board.dart';
import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _trailKey = ValueKey('draughts-last-move-trail');

Future<void> _show(
  WidgetTester tester,
  DraughtsSession session, {
  bool flipped = false,
  bool reducedMotion = false,
  Cell? selected,
  List<Cell> pendingPath = const [],
  ValueChanged<Cell>? onCell,
}) => tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 408,
            child: DraughtsBoard(
              session: session,
              onCell: onCell ?? (_) {},
              flipped: flipped,
              selected: selected,
              pendingPath: pendingPath,
            ),
          ),
        ),
      ),
    ),
  ),
);

void _expectPaintedPath(
  WidgetTester tester,
  List<Cell> path, {
  required int boardSize,
  bool flipped = false,
}) {
  final paint = tester.widget<CustomPaint>(find.byKey(_trailKey));
  // Exercise the production painter on a known canvas, checking every
  // segment's endpoints and directional arrow rather than only its inputs.
  void draw(Canvas canvas) =>
      paint.painter!.paint(canvas, const Size(400, 400));
  final square = 400 / boardSize;
  Offset center(Cell cell) => Offset(
    ((flipped ? boardSize - 1 - cell.col : cell.col) + .5) * square,
    ((flipped ? boardSize - 1 - cell.row : cell.row) + .5) * square,
  );

  final pattern = paints;
  for (var i = 1; i < path.length; i++) {
    pattern
      ..line(p1: center(path[i - 1]), p2: center(path[i]))
      ..line(p1: center(path[i - 1]), p2: center(path[i]))
      ..path()
      ..path();
  }
  expect(draw, pattern);
  expect(draw, paintsExactlyCountTimes(#drawLine, 2 * (path.length - 1)));
  expect(draw, paintsExactlyCountTimes(#drawPath, 2 * (path.length - 1)));
  expect(draw, paintsExactlyCountTimes(#drawCircle, 2 * path.length));
}

DraughtsSession _position(
  DraughtsVariant variant,
  Map<Cell, DraughtsPiece> pieces,
) {
  final rules = DraughtsRules.forVariant(variant);
  return DraughtsSession(
    rules,
    position: DraughtsPosition(rules.boardSize, [
      for (var row = 0; row < rules.boardSize; row++)
        for (var col = 0; col < rules.boardSize; col++) pieces[Cell(row, col)],
    ]),
    turn: Side.black,
  );
}

void main() {
  final fixtures = [
    (
      name: 'three diagonal captures',
      variant: DraughtsVariant.english,
      pieces: {
        const Cell(0, 1): const DraughtsPiece(Side.black),
        const Cell(1, 2): const DraughtsPiece(Side.white),
        const Cell(3, 4): const DraughtsPiece(Side.white),
        const Cell(5, 6): const DraughtsPiece(Side.white),
        const Cell(7, 0): const DraughtsPiece(Side.white),
      },
      path: const [Cell(0, 1), Cell(2, 3), Cell(4, 5), Cell(6, 7)],
    ),
    (
      name: 'international ten-by-ten captures',
      variant: DraughtsVariant.international,
      pieces: {
        const Cell(1, 0): const DraughtsPiece(Side.black),
        const Cell(2, 1): const DraughtsPiece(Side.white),
        const Cell(4, 3): const DraughtsPiece(Side.white),
        const Cell(6, 5): const DraughtsPiece(Side.white),
        const Cell(9, 0): const DraughtsPiece(Side.white),
      },
      path: const [Cell(1, 0), Cell(3, 2), Cell(5, 4), Cell(7, 6)],
    ),
    (
      name: 'Turkish orthogonal captures',
      variant: DraughtsVariant.turkish,
      pieces: {
        const Cell(1, 0): const DraughtsPiece(Side.black),
        const Cell(2, 0): const DraughtsPiece(Side.white),
        const Cell(3, 1): const DraughtsPiece(Side.white),
        const Cell(4, 2): const DraughtsPiece(Side.white),
        const Cell(7, 7): const DraughtsPiece(Side.white),
      },
      path: const [Cell(1, 0), Cell(3, 0), Cell(3, 2), Cell(5, 2)],
    ),
    (
      name: 'closed king capture returning to its source',
      variant: DraughtsVariant.english,
      pieces: {
        const Cell(3, 2): const DraughtsPiece(Side.black, DraughtsRank.king),
        const Cell(2, 3): const DraughtsPiece(Side.white),
        const Cell(2, 5): const DraughtsPiece(Side.white),
        const Cell(4, 5): const DraughtsPiece(Side.white),
        const Cell(4, 3): const DraughtsPiece(Side.white),
        const Cell(6, 7): const DraughtsPiece(Side.white),
      },
      path: const [Cell(3, 2), Cell(1, 4), Cell(3, 6), Cell(5, 4), Cell(3, 2)],
    ),
  ];

  for (final fixture in fixtures) {
    for (final flipped in [false, true]) {
      testWidgets('${fixture.name} has a full trail; flipped=$flipped', (
        tester,
      ) async {
        final session = _position(fixture.variant, fixture.pieces);
        await _show(tester, session, flipped: flipped);
        expect(find.byKey(_trailKey), findsNothing);
        final move = session.legalMoves().singleWhere(
          (move) => listEquals(move.path, fixture.path),
        );
        expect(session.applyMove(move), isTrue);
        await _show(tester, session, flipped: flipped);
        await tester.pumpAndSettle();
        _expectPaintedPath(
          tester,
          fixture.path,
          boardSize: session.rules.boardSize,
          flipped: flipped,
        );

        // A next-turn selection must leave the completed path intact and
        // the visual overlay must never intercept board input.
        Cell? tapped;
        await _show(
          tester,
          session,
          flipped: flipped,
          selected: fixture.path.last,
          pendingPath: [fixture.path.last],
          onCell: (cell) => tapped = cell,
        );
        _expectPaintedPath(
          tester,
          fixture.path,
          boardSize: session.rules.boardSize,
          flipped: flipped,
        );
        final cell = fixture.path.first;
        await tester.tap(
          find.byKey(ValueKey('draughts-square-${cell.row}-${cell.col}')),
        );
        expect(tapped, cell);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'trail follows the latest committed move, undo, restore and reset',
    (tester) async {
      var session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.english),
      );
      await _show(tester, session);
      final first = session.legalMoves().first;
      expect(session.applyMove(first), isTrue);
      await _show(tester, session);
      final second = session.legalMoves().first;
      expect(session.applyMove(second), isTrue);
      await _show(tester, session);
      await tester.pumpAndSettle();
      _expectPaintedPath(tester, second.path, boardSize: 8);

      expect(session.undo(), isTrue);
      await _show(tester, session);
      _expectPaintedPath(tester, first.path, boardSize: 8);

      session = DraughtsSession.fromJson(session.toJson());
      await _show(tester, session);
      _expectPaintedPath(tester, first.path, boardSize: 8);
      expect(session.undo(), isTrue);
      await _show(tester, session);
      expect(find.byKey(_trailKey), findsNothing);

      expect(session.applyMove(session.legalMoves().first), isTrue);
      await _show(tester, session);
      session = DraughtsSession(session.rules);
      await _show(tester, session);
      expect(find.byKey(_trailKey), findsNothing);
    },
  );

  testWidgets('reduced motion keeps the completed trail', (tester) async {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
    );
    await _show(tester, session, reducedMotion: true);
    final move = session.legalMoves().first;
    expect(session.applyMove(move), isTrue);
    await _show(tester, session, reducedMotion: true);
    _expectPaintedPath(tester, move.path, boardSize: 8);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
