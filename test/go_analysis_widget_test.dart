import 'package:easyplay/board.dart';
import 'package:easyplay/game_page.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/katago.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One faithful `kata-analyze` report, from Black's point of view.
const _report =
    'info move Q16 visits 900 utility -0.04 winrate 0.62 scoreLead 2.4 '
    'scoreStdev 20 prior 0.3 order 0 pv Q16 D4 '
    'info move D4 visits 300 utility -0.05 winrate 0.58 scoreLead 1.1 '
    'scoreStdev 20 prior 0.2 order 1 pv D4 Q16 '
    'rootInfo visits 1200 winrate 0.61 scoreLead 2.0';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Starting the engine loads its config through rootBundle, and a string
    // future cached by an earlier test never resolves inside this test's fake
    // async zone. Dropping the cache makes each test load the asset afresh.
    rootBundle.clear();
  });
  const kataGo = MethodChannel('easyplay/katago');
  final analyzeLines = <String>[];
  setUp(() {
    analyzeLines.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kataGo, (call) async {
          switch (call.method) {
            case 'start':
              return 'ready';
            case 'stop':
              return 'stopped';
            case 'analyze':
              analyzeLines.add((call.arguments as Map)['line'] as String);
              return {
                'reports': [_report],
                'reason': 'budget',
              };
          }
          final line = (call.arguments as Map)['line'] as String;
          if (line == 'protocol_version') return '2';
          return '';
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kataGo, null);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GamePage(
          type: GameType.go,
          goConfig: const GoConfig(boardSize: 19),
          useAndroidKataGo: true,
          // Analysis is a review feature, so it must not need an opponent.
          allowComputerMoves: false,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('开始对局'));
    await tester.pump();
    await tester.pump();
  }

  Board board(WidgetTester tester) => tester.widget<Board>(find.byType(Board));

  Future<void> tapRobotPanel(WidgetTester tester) async {
    await tester.tap(find.byTooltip('AI 与复盘'));
    await tester.pump();
  }

  Future<void> runAnalysis(WidgetTester tester) async {
    await tapRobotPanel(tester);
    // The action row holds 设置 / 分析 / 停一手 / 悔棋 / 认输.
    await tester.tap(find.byTooltip('分析'));
    await tester.pump();
    await tester.pump();
    // The result lives in the summary tab, which is not the default one.
    await tester.tap(find.text('AI 摘要'));
    await tester.pump();
  }

  Future<void> toggleOverlay(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilterChip, label));
    await tester.pump();
  }

  testWidgets('analysis fills the summary tab and marks the board', (
    tester,
  ) async {
    await open(tester);
    expect(board(tester).analysisHints, isEmpty);

    await runAnalysis(tester);

    expect(analyzeLines, hasLength(1));
    // The side to move is the one KataGo must be asked about; naming the other
    // colour would analyse a position that does not exist.
    expect(analyzeLines.single, startsWith('kata-analyze B '));
    expect(analyzeLines.single, contains('rootInfo true'));
    expect(analyzeLines.single, contains('ownership true'));

    expect(find.textContaining('黑棋胜率 61.0%'), findsOneWidget);
    expect(find.text('Q16'), findsWidgets);
    // Ranked badges follow the engine's order, not alphabetical order. Q16 is
    // model (3,15): GTP counts rows from the bottom and skips the letter I.
    expect(board(tester).analysisHints, [const Cell(3, 15), const Cell(15, 3)]);
    expect(tester.takeException(), null);
  });

  testWidgets('a move played after analysing retires the stale result', (
    tester,
  ) async {
    await open(tester);
    await runAnalysis(tester);
    expect(find.textContaining('黑棋胜率 61.0%'), findsOneWidget);

    tester.widget<Board>(find.byType(Board)).onCell(const Cell(15, 15));
    await tester.pump();
    await tester.pump();

    // Showing the old winrate next to a different board would be a lie.
    expect(find.textContaining('黑棋胜率 61.0%'), findsNothing);
    expect(board(tester).analysisHints, isEmpty);
  });

  testWidgets('ownership is only painted when the report carries it', (
    tester,
  ) async {
    await open(tester);
    await runAnalysis(tester);
    // The report has no ownership block, so nothing may be painted from it even
    // once the toggle is on.
    expect(board(tester).analysisOwnership, isNull);

    await toggleOverlay(tester, '局势');
    expect(board(tester).analysisOwnership, isNull);
    expect(tester.takeException(), null);
  });

  testWidgets('the candidate badges follow the 选点 toggle', (tester) async {
    await open(tester);
    await runAnalysis(tester);
    expect(board(tester).analysisHints, isNotEmpty);

    await toggleOverlay(tester, '选点');
    expect(board(tester).analysisHints, isEmpty);

    await toggleOverlay(tester, '选点');
    expect(board(tester).analysisHints, isNotEmpty);
  });

  testWidgets('the ownership wash follows the 局势 toggle', (tester) async {
    await open(tester);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kataGo, (call) async {
          switch (call.method) {
            case 'start':
              return 'ready';
            case 'stop':
              return 'stopped';
            case 'analyze':
              return {
                'reports': [
                  '$_report ownership '
                      '${List.generate(361, (i) => i.isEven ? 0.8 : -0.8).join(' ')}',
                ],
                'reason': 'budget',
              };
          }
          final line = (call.arguments as Map)['line'] as String;
          if (line == 'protocol_version') return '2';
          return '';
        });
    await runAnalysis(tester);
    // Off by default: the wash is only shown on request.
    expect(board(tester).analysisOwnership, isNull);
    expect(find.widgetWithText(FilterChip, '局势'), findsOneWidget);

    await toggleOverlay(tester, '局势');
    expect(board(tester).analysisOwnership, hasLength(361));
    expect(board(tester).analysisOwnership!.first, closeTo(0.8, 1e-9));

    await toggleOverlay(tester, '局势');
    expect(board(tester).analysisOwnership, isNull);
  });

  test('the analysis command names the side and asks for the extra blocks', () {
    expect(
      kataAnalyzeCommand(side: Side.white),
      'kata-analyze W interval 30 maxmoves 12 rootInfo true ownership true',
    );
    // Ownership is the expensive block, so it has to be optional.
    expect(
      kataAnalyzeCommand(side: Side.black, ownership: false, maxMoves: 5),
      isNot(contains('ownership')),
    );
    expect(
      kataAnalyzeCommand(side: Side.black, maxMoves: 5),
      contains('maxmoves 5'),
    );
  });
}
