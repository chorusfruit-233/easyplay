import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_placement.dart';
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/gomoku/widgets/gomoku_game_page.dart';
import 'package:easyplay/gomoku/widgets/gomoku_home_page.dart';

class _DelayedAi extends GomokuAi {
  final requests = <Completer<GomokuAiResult?>>[];
  int cancellations = 0;

  @override
  void cancel() => cancellations++;

  @override
  Future<GomokuAiResult?> search(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
    int? maxNodes,
    int? maxDepth,
    Duration? timeLimit,
  }) {
    final request = Completer<GomokuAiResult?>();
    requests.add(request);
    return request.future;
  }
}

Offset _point(WidgetTester tester, Cell cell) {
  final bounds = tester.getRect(find.byType(GomokuBoard));
  return bounds.topLeft +
      Offset(
        (cell.col + .5) * bounds.width / 15,
        (cell.row + .5) * bounds.height / 15,
      );
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      GoPlacementPreferences.key: GoPlacementMode.direct.name,
    });
  });

  testWidgets('首页进入双人对局、落子、悔棋并续局', (tester) async {
    await _pump(tester, const GomokuHomePage());
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地双人'));
    await tester.pumpAndSettle();
    final page = tester.widget<GomokuGamePage>(find.byType(GomokuGamePage));
    await tester.tapAt(_point(tester, const Cell(7, 7)));
    await tester.pumpAndSettle();
    expect(page.session.pieceAt(const Cell(7, 7)), Side.black);
    await tester.tapAt(_point(tester, const Cell(14, 14)));
    await tester.pumpAndSettle();
    expect(page.session.pieceAt(const Cell(14, 14)), Side.white);
    await tester.tap(find.text('悔棋'));
    await tester.pumpAndSettle();
    expect(page.session.moves.length, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('自由五子棋 · 1 手'), findsOneWidget);
    await tester.ensureVisible(find.text('自由五子棋 · 1 手'));
    await tester.tap(find.text('自由五子棋 · 1 手'));
    await tester.pumpAndSettle();
    final resumed = tester.widget<GomokuGamePage>(find.byType(GomokuGamePage));
    expect(resumed.session.pieceAt(const Cell(7, 7)), Side.black);
    expect(resumed.session.turn, Side.white);
    expect((await GomokuStorage.list()).single.moveCount, 1);
  });

  testWidgets('首页提供 AI 三种难度、执棋方和可注入联机入口', (tester) async {
    await _pump(
      tester,
      GomokuHomePage(lanBuilder: (_, _) => const Scaffold(body: Text('联机大厅'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('人机对弈'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<Side>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<GomokuAiLevel>));
    await tester.pumpAndSettle();
    expect(find.text('初级'), findsWidgets);
    expect(find.text('中级'), findsOneWidget);
    expect(find.text('高级'), findsOneWidget);
    await tester.tap(find.text('高级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('联机对弈'));
    await tester.tap(find.text('联机对弈'));
    await tester.pumpAndSettle();
    expect(find.text('联机大厅'), findsOneWidget);
  });

  testWidgets('确认认输与重开，保留旧局并保存新的对局', (tester) async {
    final session = GomokuSession()..place(const Cell(7, 7));
    await _pump(tester, GomokuGamePage(session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('认输'));
    await tester.pumpAndSettle();
    expect(session.gameOver, isFalse);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(session.winner, Side.black);
    await tester.tap(find.text('重开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(session.moves, isEmpty);
    expect(session.gameOver, isFalse);
    final records = await GomokuStorage.list();
    expect(records.length, 2);
    expect(records.last.restore().resigned, isTrue);
  });

  testWidgets('AI 思考期间悔棋取消旧结果，回复不能落到新状态', (tester) async {
    final session = GomokuSession();
    final ai = _DelayedAi();
    await _pump(
      tester,
      GomokuGamePage(session: session, aiLevel: GomokuAiLevel.beginner, ai: ai),
    );
    await tester.tapAt(_point(tester, const Cell(7, 7)));
    await tester.pump();
    expect(ai.requests.length, 1);
    expect(find.text('AI 正在思考…'), findsOneWidget);
    await tester.tap(find.text('悔棋'));
    await tester.pump();
    expect(session.moves, isEmpty);
    ai.requests.single.complete(const GomokuAiResult(Cell(7, 8), 1, 1));
    await tester.pump();
    expect(session.moves, isEmpty);
    expect(session.turn, Side.black);
    expect(ai.cancellations, greaterThan(0));
  });

  testWidgets('AI 后手悔棋回到人类回合；AI 先手的首子受保护', (tester) async {
    final session = GomokuSession();
    final ai = _DelayedAi();
    await _pump(
      tester,
      GomokuGamePage(
        session: session,
        aiLevel: GomokuAiLevel.intermediate,
        humanSide: Side.white,
        ai: ai,
      ),
    );
    ai.requests.single.complete(const GomokuAiResult(Cell(7, 7), 1, 1));
    await tester.pump();
    expect(session.moves.length, 1);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '悔棋'))
          .onPressed,
      isNull,
    );
    await tester.tapAt(_point(tester, const Cell(7, 8)));
    await tester.pump();
    ai.requests.last.complete(const GomokuAiResult(Cell(8, 7), 1, 1));
    await tester.pump();
    expect(session.moves.length, 3);
    await tester.tap(find.text('悔棋'));
    await tester.pump();
    expect(session.moves.length, 1);
    expect(session.turn, Side.white);
  });

  testWidgets('退出页面后延迟 AI 结果不能改变对局', (tester) async {
    final session = GomokuSession();
    final ai = _DelayedAi();
    await _pump(
      tester,
      GomokuGamePage(
        session: session,
        aiLevel: GomokuAiLevel.advanced,
        humanSide: Side.white,
        ai: ai,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    ai.requests.single.complete(const GomokuAiResult(Cell(7, 7), 1, 1));
    await tester.pump();
    expect(session.moves, isEmpty);
    expect(ai.cancellations, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回动画期间立即取消 AI，迟到回复不能落子或保存', (tester) async {
    final session = GomokuSession();
    final ai = _DelayedAi();
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => GomokuGamePage(
                  session: session,
                  aiLevel: GomokuAiLevel.intermediate,
                  humanSide: Side.white,
                  ai: ai,
                ),
              ),
            ),
            child: const Text('开始'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(ai.requests.length, 1);
    await tester.pageBack();
    await tester.pump();
    ai.requests.single.complete(const GomokuAiResult(Cell(7, 7), 1, 1));
    await tester.pump(const Duration(milliseconds: 10));
    expect(session.moves, isEmpty);
    expect((await GomokuStorage.list()).single.moveCount, 0);
    await tester.pumpAndSettle();
    expect(find.text('开始'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 640),
    const Size(640, 320),
    const Size(1280, 720),
  ]) {
    testWidgets('完整棋盘适应 ${size.width}×${size.height} 视口', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, GomokuGamePage(session: GomokuSession()));
      await tester.pumpAndSettle();
      final board = tester.getRect(find.byType(GomokuBoard));
      expect(board.left, greaterThanOrEqualTo(0));
      expect(board.right, lessThanOrEqualTo(size.width));
      expect(board.top, greaterThanOrEqualTo(kToolbarHeight));
      expect(board.bottom, lessThanOrEqualTo(size.height));
      expect(board.width, closeTo(board.height, .01));
      if (size.width == 640) expect(board.height, greaterThan(200));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('棋盘二次确认、滑动确认和松手落子遵循设置', (tester) async {
    final session = GomokuSession();
    final placed = <Cell>[];
    Future<void> board(GoPlacementMode mode, {bool enabled = true}) => _pump(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox.square(
            dimension: 300,
            child: GomokuBoard(
              session: session,
              onCell: placed.add,
              enabled: enabled,
              placementMode: mode,
            ),
          ),
        ),
      ),
    );
    await board(GoPlacementMode.doubleTap);
    final center = _point(tester, const Cell(7, 7));
    await tester.tapAt(center);
    await tester.pump();
    expect(placed, isEmpty);
    await tester.tapAt(center);
    await tester.pump();
    expect(placed, [const Cell(7, 7)]);
    placed.clear();
    await board(GoPlacementMode.swipeConfirm);
    await tester.tapAt(center);
    await tester.pump();
    await tester.dragFrom(center, const Offset(0, -30));
    await tester.pump();
    expect(placed, isEmpty);
    await tester.dragFrom(center, const Offset(0, 30));
    await tester.pump();
    expect(placed, isEmpty);
    await tester.tapAt(center);
    await tester.pump();
    await tester.dragFrom(center, const Offset(0, 30));
    await tester.pump();
    expect(placed, [const Cell(7, 7)]);
    placed.clear();
    await board(GoPlacementMode.pressRelease);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pump();
    expect(placed, [const Cell(7, 8)]);
    placed.clear();
    await board(GoPlacementMode.direct, enabled: false);
    await tester.tapAt(center);
    expect(placed, isEmpty);
  });

  for (final variant in GomokuVariant.values) {
    testWidgets('首页 ${variant.label} 规则传入本地、联机并随存档续局', (tester) async {
      GomokuVariant? requested;
      await _pump(
        tester,
        GomokuHomePage(
          lanBuilder: (_, value) {
            requested = value;
            return Scaffold(
              appBar: AppBar(title: const Text('联机大厅')),
              body: const SizedBox(),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<GomokuVariant>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(variant.label).last);
      await tester.pumpAndSettle();
      if (variant == GomokuVariant.renju) {
        expect(find.textContaining('采用自由开局'), findsOneWidget);
      }
      await tester.ensureVisible(find.text('联机对弈'));
      await tester.tap(find.text('联机对弈'));
      await tester.pumpAndSettle();
      expect(requested, variant);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('本地双人'));
      await tester.tap(find.text('本地双人'));
      await tester.pumpAndSettle();
      final page = tester.widget<GomokuGamePage>(find.byType(GomokuGamePage));
      expect(page.session.variant, variant);
      await tester.tapAt(_point(tester, const Cell(7, 7)));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final saved = find.text('${variant.label} · 1 手');
      await tester.ensureVisible(saved);
      await tester.pumpAndSettle();
      await tester.tap(saved);
      await tester.pumpAndSettle();
      final resumed = tester.widget<GomokuGamePage>(
        find.byType(GomokuGamePage),
      );
      expect(resumed.session.variant, variant);
      expect(resumed.session.moves.length, 1);
    });
  }

  testWidgets('点击连珠禁手空点显示原因，棋盘与存档保持不变', (tester) async {
    final session = GomokuSession(variant: GomokuVariant.renju);
    const black = [Cell(7, 6), Cell(7, 8), Cell(6, 7), Cell(8, 7)];
    for (var index = 0; index < black.length; index++) {
      expect(session.place(black[index]), isTrue);
      expect(session.place(Cell(0, index * 2)), isTrue);
    }
    final before = session.toJson();
    await _pump(tester, GomokuGamePage(session: session));
    await tester.pumpAndSettle();
    await tester.tapAt(_point(tester, const Cell(7, 7)));
    await tester.pumpAndSettle();
    expect(find.text('双活三禁手'), findsOneWidget);
    expect(session.toJson(), before);
    expect((await GomokuStorage.list()).single.restore().toJson(), before);
  });
}
