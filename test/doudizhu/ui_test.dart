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
import 'package:easyplay/doudizhu/multiplayer/card_lan.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_coordinator.dart';
import 'test_support.dart';

void main() {
  testWidgets('history is public while covered, updates live and resets', (
    tester,
  ) async {
    final controller = DouDizhuMatchController.hotseat();
    addTearDown(controller.dispose);
    controller.reveal();
    controller.act('bid', {'score': 3});
    controller.reveal();
    final card = controller.view!.hand.first;
    controller.act('play', {
      'cards': [card],
    });
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(home: DouDizhuGamePage(controller: controller)),
      );
      await tester.tap(find.byTooltip('历史出牌'));
      await tester.pumpAndSettle();
      expect(find.text('1 · 玩家 1 · 地主 · 单牌'), findsOneWidget);
      expect(find.byType(DouDizhuHand), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭历史出牌'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('历史出牌'));
    await tester.pumpAndSettle();
    controller.reveal();
    controller.act('pass');
    await tester.pump();
    expect(find.text('2 · 玩家 2 · 农民 · 不要'), findsOneWidget);
    controller.act('rematch');
    await tester.pump();
    expect(find.text('本局还没有出牌'), findsOneWidget);
    expect(find.text('1 · 玩家 1 · 地主 · 单牌'), findsNothing);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
  testWidgets('home retains five games and opens sixth entry', (tester) async {
    GameType? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(onPlay: (g) => selected = g, onSettings: () {}),
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
  testWidgets('LAN quick join shows only the password form', (tester) async {
    final origin = Uri.parse('http://192.168.1.20:8087');
    await tester.pumpWidget(
      MaterialApp(
        home: LanQuickJoinPage(room: LanWebRoom(origin, 'doudizhu', null)),
      ),
    );
    expect(find.text('快捷加入'), findsOneWidget);
    expect(find.text('斗地主 · 192.168.1.20:8087'), findsOneWidget);
    final lobby = tester.widget<DouDizhuLobbyPage>(
      find.byType(DouDizhuLobbyPage),
    );
    expect(lobby.initialOrigin, origin);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.labelText,
      '口令',
    );
    expect(find.text('创建房间'), findsNothing);
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
      tester
          .widget<DouDizhuLobbyPage>(find.byType(DouDizhuLobbyPage))
          .initialOrigin,
      origin,
    );
    expect(find.text('斗地主 · room.example:8443'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LAN entry separates creation and joining like other games', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DouDizhuHomePage()));
    await tester.tap(find.text('局域网联机'));
    await tester.pumpAndSettle();
    expect(find.byType(DouDizhuLanLobbyPage), findsOneWidget);
    expect(find.widgetWithText(ListTile, '创建房间'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '加入房间'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('加入房间'));
    await tester.pumpAndSettle();
    expect(find.text('加入斗地主房间'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.map((f) => f.decoration!.labelText), ['地址', '端口', '口令']);
    expect(fields[1].controller!.text, '8080');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '加入'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.23');
    await tester.enterText(find.byType(TextField).at(1), '70000');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '加入'));
    await tester.pump();
    expect(find.text('请输入有效端口'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'LAN host generates a PIN and waits for manual start with AI seats',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: DouDizhuLanLobbyPage()));
      await tester.runAsync(() async {
        await tester.tap(find.text('创建房间'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('创建斗地主房间'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              RegExp(r'^口令  \d{4}$').hasMatch(w.data ?? ''),
        ),
        findsOneWidget,
      );
      expect(find.text('AI 补位'), findsNWidgets(2));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '开始对局'))
            .onPressed,
        isNull,
      );
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(() async {
          await tester.ensureVisible(find.text('AI 补位').first);
          await tester.tap(find.text('AI 补位').first);
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
      }
      expect(find.text('本地 AI · 已准备'), findsNWidgets(2));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '开始对局'))
            .onPressed,
        isNotNull,
      );
      expect(find.byType(DouDizhuGamePage), findsNothing);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('LAN guest hides join form and waits until host starts', (
    tester,
  ) async {
    final coordinator = (await tester.runAsync(
      () async => CardRoomCoordinator(password: '1234'),
    ))!;
    final server = CardLanServer(coordinator);
    await tester.runAsync(() => server.start(host: '127.0.0.1', port: 0));
    addTearDown(() async {
      await coordinator.close();
      await server.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DouDizhuLobbyPage(
          initialOrigin: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '1234');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '加入'));
      await until(() => coordinator.seats[1]['ready'] == true);
    });
    await tester.pumpAndSettle();
    expect(find.text('等待开始'), findsOneWidget);
    expect(find.text('已加入斗地主房间，等待房主开始'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(DouDizhuGamePage), findsNothing);
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await coordinator.close();
      await server.close();
    });
    expect(tester.takeException(), isNull);
  });
}
