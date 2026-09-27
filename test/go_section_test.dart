import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_section_page.dart';
import 'package:easyplay/go_storage.dart';
import 'package:easyplay/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const kataGo = MethodChannel('easyplay/katago');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Starting the engine loads its config through rootBundle, and a string
    // future cached by an earlier test never resolves inside this test's fake
    // async zone. Dropping the cache makes each test load the asset afresh.
    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kataGo, (call) async {
          if (call.method != 'command') return '';
          final line = (call.arguments as Map)['line'] as String;
          if (line == 'protocol_version') return '2';
          // A legal reply keeps the engine "working"; an empty answer would trip
          // the local-play fallback and hide what this file is testing.
          if (line.startsWith('genmove')) return 'Q16';
          return '';
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kataGo, null);
  });

  Future<void> openSection(WidgetTester tester) async {
    // Tall enough that the board's whole action panel is on screen.
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.text('围棋'));
    await tester.pumpAndSettle();
  }

  Future<void> openLibrary(WidgetTester tester) async {
    await tester.tap(find.text('棋谱库'));
    await tester.pumpAndSettle();
  }

  /// Opens the board's action panel and taps one of its labelled actions.
  /// Pumps until the board holds at least [count] moves.
  ///
  /// Starting the engine and asking it for a move takes several turns of the
  /// event loop, so a fixed number of pumps is a race.
  Future<void> settleMoves(WidgetTester tester, int count) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.widget<Board>(find.byType(Board)).session.moves.length >=
          count) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> openAction(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('AI 与复盘'));
    await tester.pumpAndSettle();
    final target = find.byTooltip(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> startAiGame(WidgetTester tester) async {
    await tester.tap(find.text('AI 对弈'));
    await tester.pumpAndSettle();
    expect(find.text('新建 AI 对局'), findsOneWidget);
    await tester.tap(find.text('开始对局'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('entering Go opens a section with a two-item bottom bar', (
    tester,
  ) async {
    await openSection(tester);

    expect(find.byType(GoSectionPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
    // Exact text: the Go home page is showing, so the library's own app bar
    // title is offstage and not counted.
    expect(find.text('棋谱库'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });

  testWidgets('the home page offers 新建棋谱 and AI 对弈, and no problems', (
    tester,
  ) async {
    await openSection(tester);

    expect(find.text('快速开始'), findsOneWidget);
    expect(find.text('新建棋谱'), findsOneWidget);
    expect(find.text('AI 对弈'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
    // The reference product's daily problems and SRS queue are deliberately not
    // built, so nothing may hint that they exist.
    expect(find.text('今日题目'), findsNothing);
    expect(find.text('SRS学习'), findsNothing);
    expect(find.text('题库'), findsNothing);
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('the library tab opens on its own empty state', (tester) async {
    await openSection(tester);
    await openLibrary(tester);

    expect(find.byType(GoLibraryPage), findsOneWidget);
    expect(find.text('还没有棋谱'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });

  testWidgets('back returns to the Go home page before leaving the section', (
    tester,
  ) async {
    await openSection(tester);
    await openLibrary(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GoSectionPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    // A second back does leave, so the section is not a trap.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GoSectionPage), findsNothing);
    expect(find.text('今天，\n来一局好棋。'), findsOneWidget);
  });

  testWidgets('AI 对弈 asks for setup and then opens the board', (tester) async {
    await openSection(tester);
    await startAiGame(tester);

    expect(find.text('黑方回合'), findsOneWidget);
    // The board is its own screen: the section's bottom bar stays behind it.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('AI 与复盘'), findsOneWidget);
  });

  testWidgets('新建棋谱 opens a board with no engine', (tester) async {
    await openSection(tester);
    await tester.tap(find.text('新建棋谱'));
    await tester.pumpAndSettle();

    // The rules dialog belongs to AI 对弈; a record already knows what it is.
    expect(find.text('新建 AI 对局'), findsNothing);
    expect(find.text('黑方回合'), findsOneWidget);
    expect(find.text('电脑思考中…'), findsNothing);

    // And no engine answers: one move stays one move.
    final board = tester.widget<Board>(find.byType(Board));
    board.onCell(const Cell(15, 15));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      tester.widget<Board>(find.byType(Board)).session.moves,
      hasLength(1),
    );
  });

  testWidgets('the continue card enters the same section', (tester) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    expect(find.byType(GoSectionPage), findsOneWidget);
    expect(find.text('快速开始'), findsOneWidget);
  });

  testWidgets('a finished game appears under 继续 and reopens', (tester) async {
    await openSection(tester);
    await startAiGame(tester);

    final board = tester.widget<Board>(find.byType(Board));
    board.onCell(const Cell(15, 15));
    await settleMoves(tester, 2);

    // The stored entry keeps the opponent settings, or continuing a game would
    // silently turn it into a record.
    final stored = (await GoStorage.recentRecords()).single;
    expect(stored.vsComputer, isTrue);
    expect(stored.aiSettings, isNotNull);
    expect(stored.humanSide, Side.black);

    // Leaving the board returns to the Go home page, which must now list it.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('还没有对局'), findsNothing);
    expect(find.textContaining('第 '), findsWidgets);
    // The human took black, so the engine is the other side.
    expect(find.text('我'), findsWidgets);
    expect(find.text('电脑'), findsWidgets);

    await tester.tap(find.textContaining('第 ').first);
    await tester.pumpAndSettle();
    final reopened = tester.widget<Board>(find.byType(Board));
    expect(reopened.session.moves, isNotEmpty);

    // Continuing writes back over the same record rather than starting a new
    // one, which is what makes 继续 mean "continue" and not "copy".
    reopened.onCell(const Cell(3, 3));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect((await GoStorage.recentRecords()).length, 1);
  });

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byTooltip('AI 与复盘'));
    await tester.pumpAndSettle();
  }

  testWidgets('a game with an engine goes straight to the board actions', (
    tester,
  ) async {
    await openSection(tester);
    await startAiGame(tester);

    expect(find.byTooltip('设置'), findsNothing);
    await openPanel(tester);
    // Nothing to ask: this game was set up against the engine already.
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('认输'), findsOneWidget);
  });

  testWidgets('a record is asked AI 对弈 or 分析, and the question goes away', (
    tester,
  ) async {
    await openSection(tester);
    await tester.tap(find.text('新建棋谱'));
    await tester.pumpAndSettle();

    await openPanel(tester);
    // A record has no engine, so the panel asks what it is for.
    expect(find.widgetWithText(FilledButton, 'AI 对弈'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '分析'), findsOneWidget);
    expect(find.byTooltip('设置'), findsNothing);

    // 分析 turns the panel into the review, and the two buttons are gone.
    await tester.tap(find.widgetWithText(FilledButton, '分析'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '分析'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'AI 对弈'), findsNothing);
    expect(find.byTooltip('设置'), findsNothing);
  });

  testWidgets('AI 对弈 asks for the setup and then calls out the engine', (
    tester,
  ) async {
    await openSection(tester);
    await tester.tap(find.text('新建棋谱'));
    await tester.pumpAndSettle();

    await openPanel(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'AI 对弈'));
    await tester.pumpAndSettle();
    // The question that opened the dialog already answered the engine field.
    expect(find.text('AI 设置'), findsOneWidget);
    expect(find.text('不下棋（仅记录）'), findsNothing);
    expect(find.text('内置引擎'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    // Both entry buttons are gone, replaced by the board actions.
    expect(find.widgetWithText(FilledButton, 'AI 对弈'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('认输'), findsOneWidget);

    // And the engine really does answer now.
    tester.widget<Board>(find.byType(Board)).onCell(const Cell(15, 15));
    await settleMoves(tester, 2);
    expect(
      tester.widget<Board>(find.byType(Board)).session.moves,
      hasLength(2),
    );
  });

  testWidgets('设置 mid-game changes the opponent without restarting', (
    tester,
  ) async {
    await openSection(tester);
    await startAiGame(tester);

    final board = tester.widget<Board>(find.byType(Board));
    board.onCell(const Cell(15, 15));
    await settleMoves(tester, 2);
    final moves = tester.widget<Board>(find.byType(Board)).session.moves.length;
    expect(moves, 2);

    await openAction(tester, '设置');
    expect(find.text('AI 设置'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // Board, rules, komi and handicap are unchanged, so the game carries on
    // instead of being thrown away by a settings edit.
    expect(
      tester.widget<Board>(find.byType(Board)).session.moves.length,
      moves,
    );
  });

  testWidgets('设置 can take the engine back out of a game', (tester) async {
    await openSection(tester);
    await startAiGame(tester);

    await openAction(tester, '设置');
    await tester.pumpAndSettle();
    expect(find.text('内置引擎'), findsOneWidget);

    await tester.tap(find.text('内置引擎'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不下棋（仅记录）').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    tester.widget<Board>(find.byType(Board)).onCell(const Cell(15, 15));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // Nobody answers now.
    expect(
      tester.widget<Board>(find.byType(Board)).session.moves,
      hasLength(1),
    );
    // And the panel goes back to asking, rather than claiming 对弈.
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'AI 对弈'), findsOneWidget);
  });

  testWidgets('认输 ends the game only after it is confirmed', (tester) async {
    await openSection(tester);
    await startAiGame(tester);

    await openAction(tester, '认输');
    expect(find.text('确认认输？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.widget<Board>(find.byType(Board)).session.gameOver, isFalse);

    final resignAction = find.byTooltip('认输');
    await tester.ensureVisible(resignAction);
    await tester.tap(resignAction);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '认输'));
    await tester.pumpAndSettle();
    final ended = tester.widget<Board>(find.byType(Board)).session;
    expect(ended.gameOver, isTrue);
    expect(ended.winner, Side.white);
  });

  testWidgets('a stored game without settings still gets a card', (
    tester,
  ) async {
    // Entries written before settings were stored per game are a bare SGF
    // string; the home page must still list them instead of dropping them.
    await GoStorage.saveLast(
      '(;GM[1]FF[4]SZ[19];B[pd];W[dd])',
      gameId: 'legacy',
    );
    final records = await GoStorage.recentRecords();
    expect(records.single.sgf, contains('SZ[19]'));
    expect(records.single.vsComputer, isFalse);

    await openSection(tester);
    expect(find.text('还没有对局'), findsNothing);
    expect(find.text('黑方'), findsWidgets);
    expect(find.text('白方'), findsWidgets);
  });
}
