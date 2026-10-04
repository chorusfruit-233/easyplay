import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:easyplay/xiangqi/widgets/xiangqi_board.dart';
import 'package:easyplay/xiangqi/widgets/xiangqi_game_page.dart';

void main() {
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
    for (final flipped in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: XiangqiBoard(
                session: XiangqiSession(),
                flipped: flipped,
                onCell: (cell) => tapped = cell,
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(CustomPaint).last);
      await tester.tapAt(
        rect.topLeft + Offset(rect.width / 18, rect.width / 18),
      );
      expect(tapped, flipped ? const Cell(9, 8) : const Cell(0, 0));
      expect(rect.height, lessThanOrEqualTo(340));
    }
  });
  testWidgets('local controls play one move and undo without persistence', (
    tester,
  ) async {
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
