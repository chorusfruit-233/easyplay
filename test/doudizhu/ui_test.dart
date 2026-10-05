import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/doudizhu/doudizhu.dart';
import 'package:easyplay/doudizhu/doudizhu_match_controller.dart';
import 'package:easyplay/doudizhu/widgets/doudizhu_home_page.dart';
import 'package:easyplay/doudizhu/widgets/doudizhu_game_page.dart';
import 'package:easyplay/doudizhu/widgets/doudizhu_hand.dart';
import 'package:easyplay/doudizhu/widgets/bidding_panel.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/lan/lan_quick_join.dart';
import 'package:easyplay/doudizhu/widgets/doudizhu_lobby_page.dart';
import 'package:easyplay/main.dart';

void main() {
  testWidgets('home retains five games and opens sixth entry', (tester) async {
    GameType? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            onPlay: (g) => selected = g,
            selected: GameType.go,
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('斗地主'));
    await tester.tap(find.text('斗地主'));
    expect(selected, GameType.doudizhu);
    expect(GameType.values.length, 6);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'hotseat hides before revealing and covers immediately after bid',
    (tester) async {
      final controller = DouDizhuMatchController.hotseat();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: DouDizhuGamePage(controller: controller)),
      );
      expect(find.byType(DouDizhuHand), findsNothing);
      expect(controller.view, isNull);
      await tester.tap(find.text('已接过设备，查看手牌'));
      await tester.pump();
      expect(find.byType(DouDizhuHand), findsOneWidget);
      expect(
        tester.widget<DouDizhuHand>(find.byType(DouDizhuHand)).ids.length,
        17,
      );
      await tester.tap(find.text('叫 1 分'));
      await tester.pump();
      expect(controller.covered, isTrue);
      expect(find.byType(DouDizhuHand), findsNothing);
      expect(find.text('请把设备交给玩家 2'), findsOneWidget);
      await tester.tap(find.text('已接过设备，查看手牌'));
      await tester.pump();
      final bidding = tester.widget<BiddingPanel>(find.byType(BiddingPanel));
      expect(bidding.highest, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '叫 1 分'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('narrow portrait, landscape, twenty cards and clear selection', (
    tester,
  ) async {
    final controller = DouDizhuMatchController.hotseat();
    addTearDown(controller.dispose);
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(home: DouDizhuGamePage(controller: controller)),
      );
      if (controller.covered) {
        await tester.ensureVisible(find.text('已接过设备，查看手牌'));
        await tester.tap(find.text('已接过设备，查看手牌'));
        await tester.pump();
      }
      if (controller.state!.phase == DouDizhuPhase.bidding) {
        await tester.ensureVisible(find.text('叫 3 分'));
        await tester.tap(find.text('叫 3 分'));
        await tester.pump();
        await tester.ensureVisible(find.text('已接过设备，查看手牌'));
        await tester.tap(find.text('已接过设备，查看手牌'));
        await tester.pump();
      }
      expect(
        tester.widget<DouDizhuHand>(find.byType(DouDizhuHand)).ids.length,
        20,
      );
      final first = find.byKey(
        ValueKey(
          'card-${controller.view!.hand.reduce((a, b) => a > b ? a : b)}',
        ),
      );
      await tester.ensureVisible(first);
      await tester.tapAt(tester.getTopLeft(first) + const Offset(8, 12));
      await tester.pump();
      expect(
        tester.widget<DouDizhuHand>(find.byType(DouDizhuHand)).selected,
        isNotEmpty,
      );
      await tester.ensureVisible(find.text('清空'));
      await tester.tap(find.text('清空'));
      await tester.pump();
      expect(
        tester.widget<DouDizhuHand>(find.byType(DouDizhuHand)).selected,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('new game navigation exposes handoff mode', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DouDizhuHomePage()));
    await tester.tap(find.text('同机三人'));
    await tester.pumpAndSettle();
    expect(find.text('已接过设备，查看手牌'), findsOneWidget);
    expect(find.byType(DouDizhuHand), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('single-player opens a ready game with two local AI seats', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DouDizhuHomePage()));
    await tester.runAsync(() async {
      await tester.tap(find.text('单人对战'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byType(DouDizhuGamePage), findsOneWidget);
    final game = tester.widget<DouDizhuGamePage>(find.byType(DouDizhuGamePage));
    expect(
      game.controller.replica!.seats.where((s) => s['ai'] == true).length,
      2,
    );
    expect(game.controller.view!.hand.length, 17);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets('LAN quick join routes card rooms to the three-seat lobby', (
    tester,
  ) async {
    final origin = Uri.parse('http://192.168.1.20:8087');
    await tester.pumpWidget(
      MaterialApp(
        home: LanQuickJoinPage(room: LanWebRoom(origin, 'doudizhu', null)),
      ),
    );
    expect(find.text('斗地主 · 局域网房间'), findsOneWidget);
    final lobby = tester.widget<DouDizhuLobbyPage>(
      find.byType(DouDizhuLobbyPage),
    );
    expect(lobby.initialOrigin, origin);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      origin.origin,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('HTTPS quick join preserves its secure address scheme', (
    tester,
  ) async {
    final origin = Uri.parse('https://room.example:8443');
    await tester.pumpWidget(
      MaterialApp(home: DouDizhuLobbyPage(initialOrigin: origin)),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      origin.origin,
    );
    expect(tester.takeException(), isNull);
  });
}
