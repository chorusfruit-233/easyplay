import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/chess/widgets/chess_board.dart';
import 'package:easyplay/chess/widgets/chess_game_page.dart';
import 'package:easyplay/chess/widgets/chess_home_page.dart';
import 'package:easyplay/chess/widgets/chess_lan_pages.dart';

void main() {
  testWidgets('home contains only three match modes, no persistence UI', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ChessHomePage()));
    for (final label in ['AI 对战', '本地双人', '局域网联机']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in ['棋谱库', '继续上次', '最近对局']) {
      expect(find.text(label), findsNothing);
    }
    await tester.tap(find.text('本地双人'));
    await tester.pumpAndSettle();
    expect(find.text('白方回合'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('square-e2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('square-e4')));
    await tester.pump();
    expect(find.text('黑方回合'), findsOneWidget);
    await tester.ensureVisible(find.text('悔棋'));
    await tester.tap(find.text('悔棋'));
    await tester.pumpAndSettle();
    expect(find.text('白方回合'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地双人'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).session.moves,
      isEmpty,
    );
  });
  testWidgets('all promotion choices are shown and underpromotion is applied', (
    tester,
  ) async {
    final session = ChessSession(
      position: parseFen('4k3/P7/8/8/8/8/8/4K3 w - - 0 1'),
    );
    await tester.pumpWidget(
      MaterialApp(home: ChessGamePage(initialSession: session)),
    );
    await tester.tap(find.byKey(const ValueKey('square-a7')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('square-a8')));
    await tester.pumpAndSettle();
    expect(find.text('选择升变棋子'), findsOneWidget);
    expect(find.byType(SimpleDialogOption), findsNWidgets(4));
    await tester.tap(find.text('♘  马'));
    await tester.pumpAndSettle();
    expect(
      session.position.pieceAt(parseChessSquare('a8'))?.type,
      ChessPieceType.knight,
    );
  });
  testWidgets('board has correct square coordinates before and after flip', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ChessGamePage()));
    final a1 = find.byKey(const ValueKey('square-a1')),
        h8 = find.byKey(const ValueKey('square-h8'));
    expect(tester.getCenter(a1).dy, greaterThan(tester.getCenter(h8).dy));
    await tester.tap(find.byTooltip('翻转棋盘'));
    await tester.pump();
    expect(tester.getCenter(a1).dy, lessThan(tester.getCenter(h8).dy));
    expect(tester.getCenter(a1).dx, greaterThan(tester.getCenter(h8).dx));
  });
  testWidgets('join reacts immediately to address and PIN input', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ChessLanJoinPage()));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '192.168.1.2');
    await tester.enterText(fields.at(2), '1234');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '加入'))
          .onPressed,
      isNotNull,
    );
  });
}
