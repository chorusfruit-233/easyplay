import 'dart:async';

import 'package:easyplay/battleship/battleship.dart';
import 'package:easyplay/battleship/battleship_match_controller.dart';
import 'package:easyplay/battleship/multiplayer/battleship_protocol.dart';
import 'package:easyplay/battleship/multiplayer/battleship_replica.dart';
import 'package:easyplay/battleship/multiplayer/battleship_room_coordinator.dart';
import 'package:easyplay/battleship/widgets/battleship_board.dart';
import 'package:easyplay/battleship/widgets/battleship_game_page.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _fleet = [
  ShipPlacement(ShipType.carrier, 0, ShipDirection.horizontal),
  ShipPlacement(ShipType.battleship, 20, ShipDirection.horizontal),
  ShipPlacement(ShipType.cruiser, 40, ShipDirection.horizontal),
  ShipPlacement(ShipType.submarine, 60, ShipDirection.horizontal),
  ShipPlacement(ShipType.destroyer, 80, ShipDirection.horizontal),
];

class _QueuedPlaces implements MessageTransport {
  _QueuedPlaces(this.transport);
  final MessageTransport transport;
  final pending = <LanMessage>[];
  bool hold = true;

  @override
  Stream<LanMessage> get messages => transport.messages;
  @override
  Stream<void> get disconnections => transport.disconnections;

  @override
  void send(LanMessage message) {
    if (hold && message.body['action'] == 'place') {
      pending.add(message);
    } else {
      transport.send(message);
    }
  }

  void release({bool reject = false}) {
    for (final message in pending) {
      final body = message.body;
      transport.send(
        reject
            ? LanMessage(message.type, message.seq, {
                ...body,
                'payload': {
                  ...Map<String, Object?>.from(body['payload'] as Map),
                  'start': 99,
                },
              })
            : message,
      );
    }
    pending.clear();
  }

  @override
  Future<void> close() => transport.close();
}

Finder _key(String suffix) => find.byKey(ValueKey('battleship-$suffix'));

Future<void> _tap(WidgetTester tester, String suffix) async {
  final target = _key(suffix);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  BattleshipMatchController controller, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: BattleshipGamePage(controller: controller),
    ),
  );
}

BattleshipMatchController _battle() {
  final controller = BattleshipMatchController.hotseat();
  for (var seat = 0; seat < 2; seat++) {
    controller.reveal();
    for (final placement in _fleet) {
      controller.place(placement);
    }
    controller.ready();
  }
  controller.reveal();
  return controller;
}

void main() {
  testWidgets(
    'network placement advances after confirmation and respects later input',
    (tester) async {
      late BattleshipRoomCoordinator room;
      late BattleshipReplica host, guest;
      late _QueuedPlaces transport;
      await tester.runAsync(() async {
        room = BattleshipRoomCoordinator(password: '1234');
        final (authority, client) = MemoryTransport.pair();
        room.attach(authority, fixedSeat: BattleshipSeat.player1);
        transport = _QueuedPlaces(client);
        host = BattleshipReplica();
        await host.bind(transport, token: room.hostCredential);
        final (otherAuthority, otherClient) = MemoryTransport.pair();
        room.attach(otherAuthority);
        guest = BattleshipReplica();
        await guest.bind(otherClient, token: '1234');
        await host.waitForSnapshot(
          (r) => r.seats.every((s) => s['connected'] == true),
        );
        host.send('start');
        await host.waitForSnapshot((r) => r.started);
      });
      addTearDown(() async {
        await host.close();
        await guest.close();
        await room.close();
      });
      final controller = BattleshipMatchController.network(host);
      addTearDown(controller.dispose);
      await _mount(tester, controller);
      await _tap(tester, 'own-cell-0');
      await _tap(tester, 'place');
      expect(host.view!.ownFleet, isEmpty);
      expect(tester.widget<ChoiceChip>(_key('ship-carrier')).selected, isTrue);
      final revision = host.seq;
      await tester.runAsync(() async {
        guest.send('randomize');
        await host.waitForSnapshot((r) => r.seq > revision);
      });
      await tester.pump();
      expect(tester.widget<ChoiceChip>(_key('ship-carrier')).selected, isTrue);
      await tester.runAsync(() async {
        transport.release();
        await host.waitForSnapshot((r) => r.view!.ownFleet.length == 1);
      });
      await tester.pump();
      expect(
        tester.widget<ChoiceChip>(_key('ship-battleship')).selected,
        isTrue,
      );

      await _tap(tester, 'own-cell-20');
      await _tap(tester, 'place');
      await _tap(tester, 'ship-destroyer');
      await tester.runAsync(() async {
        transport.release();
        await host.waitForSnapshot((r) => r.view!.ownFleet.length == 2);
      });
      await tester.pump();
      expect(
        tester.widget<ChoiceChip>(_key('ship-destroyer')).selected,
        isTrue,
      );

      await _tap(tester, 'own-cell-80');
      await _tap(tester, 'place');
      await tester.runAsync(() async {
        transport.release(reject: true);
        await host.waitForSnapshot((r) => r.error != null);
      });
      await tester.pump();
      expect(
        tester.widget<ChoiceChip>(_key('ship-destroyer')).selected,
        isTrue,
      );
      expect(host.view!.ownFleet, hasLength(2));
      // A later matching view cannot revive the advance canceled by rejection.
      await tester.runAsync(() async {
        transport.hold = false;
        host.send(
          'place',
          ShipPlacement(
            ShipType.destroyer,
            80,
            ShipDirection.horizontal,
          ).toWire(),
        );
        await host.waitForSnapshot((r) => r.view!.ownFleet.length == 3);
      });
      await tester.pump();
      expect(
        tester.widget<ChoiceChip>(_key('ship-destroyer')).selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('manual rotation rejects edges; randomize and clear are usable', (
    tester,
  ) async {
    final controller = BattleshipMatchController.singlePlayer();
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    expect(find.text('舰队 0/5 · 对手已就绪'), findsOneWidget);
    await _tap(tester, 'own-cell-99');
    expect(tester.widget<FilledButton>(_key('place')).onPressed, isNull);
    expect(find.text('该位置越界或与其他舰船重叠'), findsOneWidget);
    await _tap(tester, 'rotate');
    expect(find.text('纵向'), findsOneWidget);
    await _tap(tester, 'own-cell-0');
    await _tap(tester, 'place');
    expect(controller.view!.ownFleet.single.ship, ShipType.carrier);
    expect(controller.view!.ownFleet.single.cells, [0, 10, 20, 30, 40]);
    expect(find.text('放置战列舰'), findsOneWidget);
    await _tap(tester, 'randomize');
    expect(controller.view!.ownFleet, hasLength(5));
    expect(tester.widget<FilledButton>(_key('ready')).onPressed, isNotNull);
    await _tap(tester, 'clear');
    expect(controller.view!.ownFleet, isEmpty);
    expect(tester.widget<FilledButton>(_key('ready')).onPressed, isNull);
    await _tap(tester, 'randomize');
    await _tap(tester, 'ready');
    expect(find.text('轮到你开火'), findsOneWidget);
    expect(_key('target-board'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'handoff removes both private boards until the recipient reveals',
    (tester) async {
      final controller = BattleshipMatchController.hotseat();
      addTearDown(controller.dispose);
      await _mount(tester, controller);
      expect(find.text('请把设备交给玩家 1'), findsOneWidget);
      expect(find.byType(BattleshipBoard), findsNothing);
      await _tap(tester, 'reveal');
      await _tap(tester, 'randomize');
      await _tap(tester, 'ready');
      expect(find.text('请把设备交给玩家 2'), findsOneWidget);
      expect(find.byType(BattleshipBoard), findsNothing);
      expect(_key('ship-carrier'), findsNothing);
      await _tap(tester, 'reveal');
      expect(controller.view!.seat, BattleshipSeat.player2);
      expect(controller.view!.ownFleet, isEmpty);
      await _tap(tester, 'randomize');
      await _tap(tester, 'ready');
      expect(find.text('请把设备交给玩家 1'), findsOneWidget);
      expect(find.byType(BattleshipBoard), findsNothing);
      await _tap(tester, 'reveal');
      expect(find.byType(BattleshipBoard), findsNWidgets(2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.byType(BattleshipBoard), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(BattleshipBoard), findsNothing);
      await _tap(tester, 'reveal');
      expect(find.byType(BattleshipBoard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'targets require confirmation; results, sinking, win and rematch',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = _battle();
      addTearDown(controller.dispose);
      await _mount(tester, controller);
      final target = tester
          .widgetList<BattleshipBoard>(find.byType(BattleshipBoard))
          .singleWhere((board) => board.id == 'target');
      expect(target.fleet, isEmpty);
      await _tap(tester, 'target-cell-99');
      expect(controller.shots, isEmpty);
      expect(find.text('目标 J10 · 确认后才会开火'), findsOneWidget);
      await _tap(tester, 'fire');
      expect(controller.shots.single.outcome, ShotOutcome.miss);
      expect(find.byType(BattleshipBoard), findsNothing);
      expect(find.textContaining('J10 · 未命中'), findsOneWidget);
      controller.reveal();
      controller.fire(10);
      controller.reveal();
      await tester.pump();

      // Hit every occupied enemy cell while the other player misses. Both the
      // widget and controller consume the same public chronological shot list.
      final cells = _fleet.expand((ship) => ship.cells).toList();
      final misses = [
        for (var cell = 11; cell < 100; cell++)
          if (!cells.contains(cell)) cell,
      ];
      for (var i = 0; i < cells.length - 1; i++) {
        controller.fire(cells[i]);
        controller.reveal();
        controller.fire(misses[i]);
        controller.reveal();
      }
      await tester.pump();
      expect(
        controller.shots.any((shot) => shot.outcome == ShotOutcome.hit),
        isTrue,
      );
      expect(
        controller.shots.any((shot) => shot.outcome == ShotOutcome.sunk),
        isTrue,
      );
      expect(find.bySemanticsLabel('敌方海域 A1 已击沉航母'), findsOneWidget);
      await _tap(tester, 'target-cell-81');
      await _tap(tester, 'fire');
      expect(find.text('玩家 1获胜'), findsOneWidget);
      expect(find.text('本局结束，双方舰队已公开。'), findsOneWidget);
      expect(controller.view!.enemyFleet, hasLength(5));
      await _tap(tester, 'rematch');
      expect(find.byType(BattleshipBoard), findsNothing);
      await _tap(tester, 'reveal');
      expect(controller.view!.ownFleet, isEmpty);
      expect(controller.view!.turn, BattleshipSeat.player2);
      expect(controller.shots, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('placement and battle fit $size with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = BattleshipMatchController.singlePlayer();
      addTearDown(controller.dispose);
      await _mount(tester, controller, scale: 2);
      await _tap(tester, 'randomize');
      await _tap(tester, 'ready');
      await _tap(tester, 'target-cell-42');
      expect(find.text('目标 E3 · 确认后才会开火'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
