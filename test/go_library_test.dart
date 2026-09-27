import 'package:easyplay/board.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_library_page.dart';
import 'package:easyplay/go_sgf.dart';
import 'package:easyplay/go_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A finished 13-line game, so a row has a size, a move count and a result.
/// White resigns, so Black wins.
String _finishedGame() {
  final game = GameSession(
    GameType.go,
    goConfig: const GoConfig(boardSize: 13, komi: 6.5),
  );
  game.placeGo(const Cell(3, 3));
  game.placeGo(const Cell(9, 9));
  game.resignGo(Side.white);
  return GoSgf.exportGame(game);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: GoLibraryPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty library says so and offers the import', (tester) async {
    await open(tester);

    expect(find.text('还没有棋谱'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '导入 SGF'), findsOneWidget);
    expect(find.byTooltip('导入 SGF'), findsOneWidget);
  });

  testWidgets('a stored game is listed with its size, moves and result', (
    tester,
  ) async {
    await GoStorage.addRecord(_finishedGame());
    await open(tester);

    expect(find.text('还没有棋谱'), findsNothing);
    expect(find.byType(ListTile), findsOneWidget);
    // Board size, move count and result, all read back out of the SGF.
    expect(find.text('13 路 · 第 2 手 · 黑胜'), findsOneWidget);
    expect(find.text('黑方'), findsOneWidget);
    expect(find.text('白方'), findsOneWidget);
  });

  testWidgets('newest first, so the list reads like a history', (tester) async {
    await GoStorage.addRecord(
      GoSgf.exportGame(GameSession(GameType.go)),
      humanSide: Side.white,
    );
    await GoStorage.addRecord(_finishedGame());
    final records = await GoStorage.recentRecords();
    // The store keeps them newest first; the page must not reorder them.
    expect(records.first.sgf, contains('SZ[13]'));

    await open(tester);
    expect(find.text('13 路 · 第 2 手 · 黑胜'), findsOneWidget);
    expect(find.text('19 路 · 第 0 手 · 进行中'), findsOneWidget);
  });

  testWidgets('tapping a row opens the game on the board', (tester) async {
    await GoStorage.addRecord(_finishedGame());
    await open(tester);

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    // The board is the editor; the library only manages files.
    expect(find.byType(Board), findsOneWidget);
    expect(
      tester.widget<Board>(find.byType(Board)).session.moves,
      hasLength(2),
    );
  });

  testWidgets('swiping a row deletes it only after it is confirmed', (
    tester,
  ) async {
    await GoStorage.addRecord(_finishedGame());
    await open(tester);

    await tester.drag(find.byType(ListTile), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除棋谱？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await GoStorage.recentRecords(), hasLength(1));
    expect(find.byType(ListTile), findsOneWidget);

    await tester.drag(find.byType(ListTile), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(await GoStorage.recentRecords(), isEmpty);
    expect(find.text('还没有棋谱'), findsOneWidget);
  });

  testWidgets('deleting the resume slot clears it too', (tester) async {
    // The library row and the "continue" slot are the same game here, so
    // deleting the row must not leave a game behind that resumes on its own.
    final record = await GoStorage.addRecord(_finishedGame());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('easyplay.last_go_sgf', record.sgf);
    await prefs.setString('easyplay.last_go_id', record.id);

    await GoStorage.deleteRecord(record.id);

    expect(await GoStorage.loadLast(), isNull);
    expect(await GoStorage.lastId(), isNull);
  });

  testWidgets('an unreadable entry is listed rather than silently dropped', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('easyplay.go_records', ['not an sgf at all']);
    await open(tester);

    // Hiding it would make a saved game look lost; the row says what it knows.
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('未命名棋谱'), findsOneWidget);
    expect(find.textContaining('无法读取'), findsOneWidget);
  });

  test('importing parses before storing', () async {
    final record = await importKifu(_finishedGame());
    expect((await GoStorage.recentRecords()).single.id, record.id);

    // A file that cannot be read must not enter the library at all; storing it
    // would only defer the failure to every later open.
    await expectLater(importKifu('this is not an sgf'), throwsA(anything));
    expect(await GoStorage.recentRecords(), hasLength(1));
  });

  testWidgets('imported games show up in the list', (tester) async {
    await importKifu(_finishedGame());
    await open(tester);

    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('13 路 · 第 2 手 · 黑胜'), findsOneWidget);
  });
}
