import 'dart:async';
import 'dart:io';

import 'package:easyplay/battleship/battleship.dart';
import 'package:easyplay/battleship/multiplayer/battleship_lan.dart';
import 'package:easyplay/battleship/multiplayer/battleship_replica.dart';
import 'package:easyplay/battleship/multiplayer/battleship_room_coordinator.dart';
import 'package:easyplay/battleship/widgets/battleship_game_page.dart';
import 'package:easyplay/battleship/widgets/battleship_lobby_page.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Room update did not arrive');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  testWidgets('leaving while LAN connects closes the eventual socket', (
    tester,
  ) async {
    final upgrade = Completer<void>();
    final closed = Completer<void>();
    var requested = false;
    late HttpServer server;
    WebSocket? socket;
    await tester.runAsync(() async {
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        requested = true;
        await upgrade.future;
        socket = await WebSocketTransformer.upgrade(request);
        socket!.listen((_) {}, onDone: closed.complete);
      });
    });
    addTearDown(() async {
      await socket?.close();
      await server.close(force: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipLobbyPage(
          initialOrigin: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '1234');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '加入'));
      await _until(() => requested);
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      upgrade.complete();
      await _until(() => socket != null);
    });
    for (var i = 0; i < 20 && !closed.isCompleted; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    }
    expect(closed.isCompleted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'LAN entry separates creation and joining and validates the port',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: BattleshipLanLobbyPage()),
      );
      expect(find.text('创建房间'), findsOneWidget);
      expect(find.text('加入房间'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('加入房间'));
      await tester.pumpAndSettle();
      expect(find.text('加入海战棋房间'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.map((field) => field.decoration!.labelText), [
        '地址',
        '端口',
        '口令',
      ]);
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
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'LAN host generates a four-digit PIN and requires another player',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: BattleshipLanLobbyPage()),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('创建房间'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('创建海战棋房间'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              RegExp(r'^口令  \d{4}$').hasMatch(widget.data ?? ''),
        ),
        findsOneWidget,
      );
      expect(find.text('经典双人海战棋 · 玩家 1/2'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '开始对局'))
            .onPressed,
        isNull,
      );
      expect(find.byType(BattleshipGamePage), findsNothing);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'LAN guest waits for start, reconnects its fleet, and returns to the lobby',
    (tester) async {
      late BattleshipRoomCoordinator room;
      late BattleshipLanServer server;
      late BattleshipReplica host;
      await tester.runAsync(() async {
        room = BattleshipRoomCoordinator(password: '1234');
        server = BattleshipLanServer(room);
        await server.start(host: '127.0.0.1', port: 0);
        final (authority, client) = MemoryTransport.pair();
        room.attach(authority, fixedSeat: BattleshipSeat.player1);
        host = BattleshipReplica();
        await host.bind(client, token: room.hostCredential);
      });
      addTearDown(() async {
        await host.close();
        await room.close();
        await server.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: BattleshipLobbyPage(
            initialOrigin: Uri.parse('http://127.0.0.1:${server.port}'),
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, '加入'));
        await tester.pump();
        await _until(() => room.playerCount == 2);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.text('已加入海战棋房间，等待房主开始'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(BattleshipGamePage), findsNothing);
      await tester.runAsync(() async {
        await _until(() => host.seq == room.seq);
        host.send('start');
        await host.waitForSnapshot((replica) => replica.started);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.byType(BattleshipGamePage), findsOneWidget);
      final controller = tester
          .widget<BattleshipGamePage>(find.byType(BattleshipGamePage))
          .controller;
      await tester.runAsync(() async {
        controller.randomize();
        await _until(() => controller.view!.ownFleet.length == 5);
      });
      await tester.pumpAndSettle();
      final fleet = controller.view!.ownFleet;
      await tester.runAsync(() async {
        await room.disconnectSeat(BattleshipSeat.player2);
        await _until(() => !controller.connected);
      });
      await tester.pumpAndSettle();
      expect(controller.canAct, isFalse);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('battleship-randomize')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('重新连接'));
      await tester.runAsync(() async {
        await tester.tap(find.text('重新连接'));
        await _until(() => controller.connected);
      });
      await tester.pumpAndSettle();
      expect(controller.view!.ownFleet, fleet);
      expect(controller.view!.seat, BattleshipSeat.player2);
      expect(controller.view!.enemyFleet, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('返回对局'), findsOneWidget);
      expect(room.allConnected, isTrue);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('LAN and RTC forms fit $size with larger text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> mount(Widget child) => tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: child,
        ),
      );
      await mount(const BattleshipLobbyPage(key: ValueKey('lan')));
      expect(find.text('地址'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == '口令',
        ),
        120,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      await mount(const BattleshipLobbyPage(key: ValueKey('rtc'), rtc: true));
      expect(find.text('连接选项'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '{}');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final join = find.text('加入 / 重连并生成回应');
      await tester.ensureVisible(join);
      await tester.pumpAndSettle();
      await tester.tap(join);
      await tester.pump();
      expect(find.text('海战棋邀请格式无效'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
