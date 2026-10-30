import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:easyplay/xiangqi/widgets/xiangqi_board.dart';
import 'package:easyplay/xiangqi/widgets/xiangqi_game_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'board preserves its aspect ratio within both parent dimensions',
    (tester) async {
      for (final (available, expected) in [
        (const Size(500, 220), const Size(198, 220)),
        (const Size(120, 500), const Size(120, 400 / 3)),
        (const Size(500, 70), const Size(63, 70)),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox.fromSize(
                  size: available,
                  child: XiangqiBoard(session: XiangqiSession()),
                ),
              ),
            ),
          ),
        );
        final board = tester.getSize(
          find.descendant(
            of: find.byType(XiangqiBoard),
            matching: find.byType(CustomPaint),
          ),
        );
        expect(board.width, closeTo(expected.width, .001));
        expect(board.height, closeTo(expected.height, .001));
        expect(board.aspectRatio, closeTo(9 / 10, .001));
        expect(board.width, lessThanOrEqualTo(available.width));
        expect(board.height, lessThanOrEqualTo(available.height));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('late system fonts invalidate the painted piece labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: XiangqiBoard(session: XiangqiSession())),
      ),
    );
    final finder = find.descendant(
      of: find.byType(XiangqiBoard),
      matching: find.byType(CustomPaint),
    );
    final render = tester.renderObject<RenderCustomPaint>(finder);
    expect(render.debugNeedsPaint, isFalse);
    await tester.binding.handleSystemMessage({'type': 'fontsChange'});
    expect(render.debugNeedsPaint, isTrue);
    await tester.pump();
    expect(render.debugNeedsPaint, isFalse);
  });
  testWidgets('intersection taps preserve internal coordinates when flipped', (
    tester,
  ) async {
    Cell? tapped;
    for (final available in [const Size(500, 220), const Size(120, 500)]) {
      for (final flipped in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox.fromSize(
                  size: available,
                  child: XiangqiBoard(
                    session: XiangqiSession(),
                    flipped: flipped,
                    onCell: (cell) => tapped = cell,
                  ),
                ),
              ),
            ),
          ),
        );
        final rect = tester.getRect(find.byType(CustomPaint).last);
        for (final cell in [
          const Cell(0, 0),
          const Cell(0, 8),
          const Cell(9, 0),
          const Cell(9, 8),
          const Cell(6, 2),
        ]) {
          tapped = null;
          await tester.tapAt(
            rect.topLeft +
                Offset(
                  (cell.col + .5) * rect.width / 9,
                  (cell.row + .5) * rect.height / 10,
                ),
          );
          expect(tapped, flipped ? Cell(9 - cell.row, 8 - cell.col) : cell);
        }
      }
    }
  });
  testWidgets('local controls play one move and undo', (tester) async {
    final session = XiangqiSession();
    await tester.pumpWidget(
      MaterialApp(home: XiangqiGamePage(initialSession: session)),
    );
    final board = tester.getRect(find.byType(XiangqiBoard));
    // XiangqiBoard centers a constrained painter inside its parent.
    final painter = tester.getRect(
      find.descendant(
        of: find.byType(XiangqiBoard),
        matching: find.byType(CustomPaint),
      ),
    );
    final step = painter.width / 9;
    await tester.tapAt(painter.topLeft + Offset(step * 7.5, step * 7.5));
    await tester.pump();
    await tester.tapAt(painter.topLeft + Offset(step * 4.5, step * 7.5));
    await tester.pump();
    expect(session.moves.length, 1);
    await tester.ensureVisible(find.text('悔棋'));
    await tester.tap(find.text('悔棋'));
    await tester.pump();
    expect(session.moves, isEmpty);
    expect(board.width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
