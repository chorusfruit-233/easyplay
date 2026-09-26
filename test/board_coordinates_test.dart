import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/board.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_placement.dart';

/// Hosts a bare Board at a known square size. Going through GamePage would drag
/// in the setup sheet and preferences; the mapping under test lives entirely in
/// Board, so a direct host keeps the assertions about geometry only.
class _Host extends StatelessWidget {
  final GameSession session;
  final GameType type;
  final List<Cell> taps;
  final double side;
  const _Host({
    required this.session,
    required this.type,
    required this.taps,
    this.side = 380,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: side,
          height: side,
          child: Board(
            type: type,
            session: session,
            selected: null,
            targets: const [],
            placementMode: GoPlacementMode.direct,
            onCell: taps.add,
          ),
        ),
      ),
    ),
  );
}

void main() {
  /// Taps the centre of intersection (row, col) and returns what Board reported.
  Future<Cell> tapIntersection(
    WidgetTester tester, {
    required GameSession session,
    required GameType type,
    required int row,
    required int col,
    double side = 380,
  }) async {
    final taps = <Cell>[];
    await tester.pumpWidget(
      _Host(session: session, type: type, taps: taps, side: side),
    );
    final rect = tester.getRect(find.byType(Board));
    final step = rect.width / session.size;
    // BoardPainter draws intersection (r, c) at (c + .5) * step, (r + .5) * step.
    await tester.tapAt(
      rect.topLeft + Offset((col + 0.5) * step, (row + 0.5) * step),
    );
    await tester.pump();
    expect(taps, hasLength(1), reason: '该坐标应命中一个交叉点');
    return taps.single;
  }

  testWidgets('every intersection round-trips to itself', (tester) async {
    for (final size in [9, 13, 19]) {
      final session = GameSession(
        GameType.go,
        goConfig: GoConfig(boardSize: size),
      );
      for (final row in [0, 1, size ~/ 2, size - 2, size - 1]) {
        for (final col in [0, 1, size ~/ 2, size - 2, size - 1]) {
          final hit = await tapIntersection(
            tester,
            session: session,
            type: GameType.go,
            row: row,
            col: col,
          );
          expect(hit, Cell(row, col), reason: '$size 路：应命中 ($row,$col)');
        }
      }
    }
  });

  testWidgets('row comes from dy and column from dx', (tester) async {
    final session = GameSession(
      GameType.go,
      goConfig: const GoConfig(boardSize: 19),
    );

    // A transposed tap must yield the transposed cell; if the two axes were
    // swapped this pair would still be self-consistent, so assert both.
    final a = await tapIntersection(
      tester,
      session: session,
      type: GameType.go,
      row: 3,
      col: 11,
    );
    final b = await tapIntersection(
      tester,
      session: session,
      type: GameType.go,
      row: 11,
      col: 3,
    );
    expect(a, const Cell(3, 11));
    expect(b, const Cell(11, 3));
  });

  testWidgets('midpoints round towards the nearest intersection', (
    tester,
  ) async {
    final session = GameSession(
      GameType.go,
      goConfig: const GoConfig(boardSize: 19),
    );
    const side = 380.0;
    final taps = <Cell>[];
    await tester.pumpWidget(
      _Host(session: session, type: GameType.go, taps: taps, side: side),
    );
    final rect = tester.getRect(find.byType(Board));
    final step = rect.width / 19;

    // Just past the (4,4) centre pulls towards row/col 4.
    await tester.tapAt(
      rect.topLeft + Offset(4.5 * step + step * 0.3, 4.5 * step + step * 0.3),
    );
    await tester.pump();
    expect(taps.last, const Cell(4, 4));

    // Just before the (5,5) centre pulls towards row/col 5.
    await tester.tapAt(
      rect.topLeft + Offset(5.5 * step - step * 0.3, 5.5 * step - step * 0.3),
    );
    await tester.pump();
    expect(taps.last, const Cell(5, 5));
  });

  testWidgets('taps outside the board are ignored', (tester) async {
    final session = GameSession(
      GameType.go,
      goConfig: const GoConfig(boardSize: 19),
    );
    const side = 380.0;
    final taps = <Cell>[];
    await tester.pumpWidget(
      _Host(session: session, type: GameType.go, taps: taps, side: side),
    );
    final rect = tester.getRect(find.byType(Board));
    final step = rect.width / 19;

    // Past the last line by more than half a cell.
    await tester.tapAt(rect.topLeft + Offset(19.4 * step, 4.5 * step));
    await tester.pump();
    expect(taps, isEmpty, reason: '右侧越界不应命中');

    await tester.tapAt(rect.topLeft + Offset(4.5 * step, 19.4 * step));
    await tester.pump();
    expect(taps, isEmpty, reason: '下方越界不应命中');

    // Just beyond the last line still rounds away (19.2 -> 18.7 -> 19).
    await tester.tapAt(rect.topLeft + Offset(19.2 * step, 4.5 * step));
    await tester.pump();
    expect(taps, isEmpty, reason: '刚越过最后一线也不应命中');

    // The outermost intersection itself is still reachable.
    await tester.tapAt(rect.topLeft + Offset(18.5 * step, 18.5 * step));
    await tester.pump();
    expect(taps, hasLength(1));
    expect(taps.single, const Cell(18, 18));

    // Inside the widget the rounded row/col can never fall below 0: for a local
    // y in [0, step/2) the expression round((y - step/2)/step) yields 0 at
    // worst. The lower-bound half of inside() is therefore unreachable from a
    // tap and is covered by the direct session test instead. What a tap can do
    // is overshoot the far edge, which is asserted above.
    var before = taps.length;
    await tester.tapAt(rect.topLeft + Offset(4.5 * step, 0.01 * step));
    await tester.pump();
    expect(taps.length, before + 1, reason: '首线之上仍是合法交叉点 (0,4)');
    expect(taps.last, const Cell(0, 4));
    before = taps.length;
    await tester.tapAt(rect.topLeft + Offset(0.01 * step, 4.5 * step));
    await tester.pump();
    expect(taps.length, before + 1, reason: '首线之左仍是合法交叉点 (4,0)');
    expect(taps.last, const Cell(4, 0));
  });

  // inside() bounds the cell on all four sides. The tap path can only reach the
  // far edge, so the near edge and the lower-bound guards are asserted here.
  test('inside() bounds rows and columns on all four sides', () {
    for (final size in [9, 13, 19]) {
      final session = GameSession(
        GameType.go,
        goConfig: GoConfig(boardSize: size),
      );
      expect(session.inside(const Cell(0, 0)), isTrue);
      expect(session.inside(Cell(size - 1, size - 1)), isTrue);
      expect(session.inside(Cell(-1, 0)), isFalse, reason: '负行越界');
      expect(session.inside(Cell(0, -1)), isFalse, reason: '负列越界');
      expect(session.inside(Cell(size, 0)), isFalse, reason: '行越界');
      expect(session.inside(Cell(0, size)), isFalse, reason: '列越界');
    }
  });

  testWidgets('chess maps by cell index rather than intersection', (
    tester,
  ) async {
    final session = GameSession(GameType.chess);
    final taps = <Cell>[];
    await tester.pumpWidget(
      _Host(session: session, type: GameType.chess, taps: taps),
    );
    final rect = tester.getRect(find.byType(Board));
    final step = rect.width / 8;

    // Chess uses floor(dx / step): the cell origin is its top-left corner, so
    // the centre of a square must land in that square.
    await tester.tapAt(rect.topLeft + Offset(2.5 * step, 5.5 * step));
    await tester.pump();
    expect(taps.single, const Cell(5, 2));
  });
}
