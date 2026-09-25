import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_sgf.dart';
import 'package:easyplay/go_storage.dart';
import 'package:easyplay/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const kataGo = MethodChannel('easyplay/katago');
  var boardSize = 19;
  setUp(() {
    boardSize = 19;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kataGo, (call) async {
          if (call.method == 'start') return 'ready';
          if (call.method == 'stop') return 'stopped';
          final line = (call.arguments as Map)['line'] as String;
          if (line.startsWith('boardsize ')) {
            boardSize = int.parse(line.substring('boardsize '.length));
          }
          if (line == 'protocol_version') return '2';
          if (line == 'final_status_list dead') return 'E15';
          if (line == 'final_score') return 'W+6.5';
          if (line == 'genmove W') return 'B$boardSize';
          return '';
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kataGo, null);
  });

  Future<void> open(
    WidgetTester tester, {
    GoConfig? config,
    double width = 1100,
    bool useAndroidKataGo = false,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GamePage(
          type: GameType.go,
          goConfig: config,
          useAndroidKataGo: useAndroidKataGo,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('新建 AI 对局'), findsOneWidget);
    await tester.tap(find.text('开始对局'));
    await tester.pump();
    await tester.pump();
  }

  GameSession session(WidgetTester tester) =>
      tester.widget<Board>(find.byType(Board)).session;
  Future<void> menu(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('tap location maps to actual 19-line intersection', (
    tester,
  ) async {
    await open(tester, config: const GoConfig(boardSize: 19));
    final rect = tester.getRect(find.byType(Board));
    final step = rect.width / 19;
    await tester.tapAt(rect.topLeft + Offset(step * 3.5, step * 3.5));
    await tester.pump();
    expect(session(tester).pieceAt(const Cell(3, 3))?.side, Side.black);
    expect(find.textContaining('D16'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('320px game controls fit without overflow', (tester) async {
    await open(tester, width: 320);
    await tester.ensureVisible(find.text('本地双人'));
    await tester.tap(find.text('本地双人'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });

  testWidgets('19-line coordinates and AI response are persisted as one game', (
    tester,
  ) async {
    await open(
      tester,
      config: const GoConfig(boardSize: 19),
      useAndroidKataGo: true,
    );
    final board = tester.widget<Board>(find.byType(Board));
    board.onCell(const Cell(18, 18));
    await tester.pump();
    expect(find.textContaining('T1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(session(tester).moves.length, 2);
    final saved = await GoStorage.loadLast();
    expect(GoSgf.importGame(saved!).moves.length, 2);
    expect(await GoStorage.records(), hasLength(1));
    expect(tester.takeException(), null);
  });

  testWidgets('restart cancels pending computer move', (tester) async {
    await open(tester);
    tester.widget<Board>(find.byType(Board)).onCell(const Cell(4, 4));
    await tester.pump();
    await tester.tap(find.text('重新开始'));
    await tester.pump(const Duration(seconds: 1));
    expect(session(tester).moves, isEmpty);
    expect(session(tester).turn, Side.black);
    expect(find.text('电脑思考中…'), findsNothing);
    expect(GoSgf.importGame((await GoStorage.loadLast())!).moves, isEmpty);
  });

  testWidgets('handicap starts white and restart preserves handicap', (
    tester,
  ) async {
    await open(tester, config: const GoConfig(boardSize: 13, handicap: 6));
    expect(session(tester).moves, isEmpty);
    expect(session(tester).turn, Side.white);
    await tester.tap(find.text('重新开始'));
    await tester.pump();
    expect(session(tester).moves, isEmpty);
    expect(session(tester).turn, Side.white);
    expect(session(tester).goConfig.handicap, 6);
    expect(
      session(
        tester,
      ).board.expand((row) => row).where((piece) => piece != null),
      hasLength(6),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('scoring, mark, confirm and resume work on narrow screen', (
    tester,
  ) async {
    await open(tester, width: 390);
    await tester.ensureVisible(find.text('本地双人'));
    await tester.tap(find.text('本地双人'));
    await tester.pump();
    tester.widget<Board>(find.byType(Board)).onCell(const Cell(4, 4));
    await tester.pump();
    await menu(tester, '停一手');
    await menu(tester, '停一手');
    expect(find.text('待确认计分'), findsOneWidget);
    tester.widget<Board>(find.byType(Board)).onCell(const Cell(4, 4));
    await tester.pump();
    final painter =
        tester
                .widgetList<CustomPaint>(
                  find.descendant(
                    of: find.byType(Board),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .single
                .painter
            as BoardPainter;
    expect(painter.deadStones, {const Cell(4, 4)});
    await tester.ensureVisible(find.text('确认计分'));
    await tester.tap(find.text('确认计分'));
    await tester.pump();
    expect(session(tester).goScoreConfirmed, true);
    await tester.ensureVisible(find.text('继续对局'));
    await tester.tap(find.text('继续对局'));
    await tester.pump();
    expect(session(tester).gameOver, false);
    expect(session(tester).deadGoStones, isEmpty);
    expect(tester.takeException(), null);
  });

  testWidgets('double pass stays manually adjudicable without KataGo', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.text('本地双人'));
    await tester.tap(find.text('本地双人'));
    await tester.pump();
    tester.widget<Board>(find.byType(Board)).onCell(const Cell(4, 4));
    await tester.pump();
    await menu(tester, '停一手');
    await menu(tester, '停一手');
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(session(tester).gameOver, isTrue);
    expect(session(tester).goScoreConfirmed, isFalse);
    expect(find.text('待确认计分'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid komi cannot reset the game', (tester) async {
    await open(tester, width: 390);
    await menu(tester, '棋盘与规则设置');
    await tester.enterText(find.byType(TextFormField).last, 'NaN');
    await tester.tap(find.text('应用并重开'));
    await tester.pump();
    expect(find.text('请输入 -100 至 100 的贴目'), findsOneWidget);
    expect(session(tester).goConfig.komi, 7.5);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });

  testWidgets('restore loads saved rules, moves and local mode', (
    tester,
  ) async {
    final g = GameSession(
      GameType.go,
      goConfig: const GoConfig(boardSize: 13, komi: 6.5),
    );
    g.placeGo(const Cell(10, 10));
    await GoStorage.saveLast(
      GoSgf.exportGame(g),
      gameId: 'saved',
      vsComputer: false,
    );
    await open(tester);
    // Starting a fresh game persists its initial state, so seed the recovery
    // fixture after the required first-game settings flow has completed.
    await GoStorage.saveLast(
      GoSgf.exportGame(g),
      gameId: 'saved',
      vsComputer: false,
    );
    await menu(tester, '恢复上次对局');
    expect(session(tester).size, 13);
    expect(session(tester).moves.length, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(session(tester).moves.length, 1);
    expect(await GoStorage.lastId(), 'saved');
    expect(tester.takeException(), null);
  });
}
