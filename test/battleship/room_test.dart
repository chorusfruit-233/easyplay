import 'dart:convert';
import 'dart:math';

import 'package:easyplay/battleship/battleship.dart';
import 'package:easyplay/battleship/multiplayer/battleship_protocol.dart';
import 'package:easyplay/battleship/multiplayer/battleship_replica.dart';
import 'package:easyplay/battleship/multiplayer/battleship_room_coordinator.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'network_test_support.dart';

void main() {
  test('local host stays connected after a suspended lobby and can start', () {
    fakeAsync((time) {
      final room = BattleshipRoomCoordinator(password: 'room-pin');
      final host = BattleshipReplica(), guest = BattleshipReplica();
      final (authority, client) = MemoryTransport.pair();
      room.attach(authority, fixedSeat: BattleshipSeat.player1);
      var pings = 0;
      host.onWireMessage = (raw) {
        if (LanMessage.decode(raw).body['action'] == 'ping') pings++;
      };
      host.bind(client, token: room.hostCredential);
      time.flushMicrotasks();
      expect(host.connected, isTrue);
      expect(time.periodicTimerCount, 1); // The remote-seat watchdog only.
      time.elapseBlocking(const Duration(minutes: 5));
      time.elapse(const Duration(seconds: 5));
      expect(pings, 0);
      expect(host.connected, isTrue);
      expect(room.seats[0]['connected'], isTrue);
      final (remote, endpoint) = MemoryTransport.pair();
      room.attach(remote);
      guest.bind(endpoint, token: room.password);
      time.flushMicrotasks();
      expect(room.canStart, isTrue);
      host.send('start');
      time.flushMicrotasks();
      expect(host.started && guest.started, isTrue);
      host.close();
      guest.close();
      room.close();
      time.flushMicrotasks();
      expect(time.pendingTimers, isEmpty);
    });
  });

  test(
    'host starts; simultaneous private fleet edits and locks both survive',
    () async {
      final room = BattleshipRoomCoordinator(password: '1234');
      final (host, _) = await join(room, host: true);
      final (guest, _) = await join(room);
      addTearDown(() async {
        await host.close();
        await guest.close();
        await room.close();
      });
      expect(room.canStart, isTrue);
      final old = room.seq;
      guest.send('start');
      await until(() => guest.error != null);
      expect(room.seq, old);
      expect(room.started, isFalse);
      await submit(room, host, 'start');
      await until(() => host.seq == guest.seq);
      host.send(
        'place',
        ShipPlacement(ShipType.carrier, 0, ShipDirection.horizontal).toWire(),
      );
      guest.send(
        'place',
        ShipPlacement(
          ShipType.destroyer,
          98,
          ShipDirection.horizontal,
        ).toWire(),
      );
      await until(
        () =>
            host.view!.ownFleet.length == 1 && guest.view!.ownFleet.length == 1,
      );
      expect(host.view!.ownFleet.single.ship, ShipType.carrier);
      expect(guest.view!.ownFleet.single.ship, ShipType.destroyer);
      expect(host.view!.enemyFleet, isEmpty);
      expect(guest.view!.enemyFleet, isEmpty);
      await until(() => host.seq == room.seq && guest.seq == room.seq);
      host.send('randomize');
      guest.send('randomize');
      await until(
        () =>
            host.view!.ownFleet.length == 5 && guest.view!.ownFleet.length == 5,
      );
      await until(() => host.seq == room.seq && guest.seq == room.seq);
      host.send('ready');
      guest.send('ready');
      await until(
        () =>
            host.view!.phase == BattleshipPhase.playing &&
            guest.view!.phase == BattleshipPhase.playing,
      );
      expect(room.session.phase, BattleshipPhase.playing);
      final locked = jsonEncode(
        host.view!.ownFleet.map((s) => s.toWire()).toList(),
      );
      final before = room.seq;
      host.send('clear');
      await until(() => host.error != null);
      expect(room.seq, before);
      expect(
        jsonEncode(host.view!.ownFleet.map((s) => s.toWire()).toList()),
        locked,
      );
    },
  );

  test(
    'opaque resume identity reserves seat and pauses until authentic reconnect',
    () async {
      final room = BattleshipRoomCoordinator(password: '1234');
      final (host, _) = await join(room, host: true);
      final (guest, _) = await join(room);
      addTearDown(() async {
        await host.close();
        await guest.close();
        await room.close();
      });
      await begin(room, host, guest);
      final fleet = guest.view!.ownFleet.toList();
      await guest.disconnect();
      await until(
        () => !room.allConnected && host.seats[1]['connected'] == false,
      );
      final old = room.seq;
      host.send('fire', {'cell': 0});
      await until(() => host.error != null);
      expect(room.seq, old);
      expect(host.view!.shots, isEmpty);
      for (final token in ['wrong', '1234', room.hostCredential]) {
        final attacker = BattleshipReplica();
        final (server, client) = MemoryTransport.pair();
        room.attach(server);
        await expectLater(
          attacker.bind(client, token: token),
          throwsStateError,
        );
        await attacker.close();
      }
      await join(room, replica: guest);
      await until(
        () => room.allConnected && host.seats[1]['connected'] == true,
      );
      expect(guest.view!.seat, BattleshipSeat.player2);
      expect(guest.view!.ownFleet, fleet);
      await submit(room, host, 'fire', {'cell': 0});
      expect(host.view!.shots.length, 1);
    },
  );

  test(
    'accepted and rejected requests cannot replay on another turn or rematch',
    () async {
      final room = BattleshipRoomCoordinator(
        password: '1234',
        session: BattleshipSession(random: Random(3)),
      );
      final (host, hostTransport) = await join(room, host: true);
      final (guest, guestTransport) = await join(room);
      addTearDown(() async {
        await host.close();
        await guest.close();
        await room.close();
      });
      await begin(room, host, guest);
      guest.send('fire', {'cell': 99});
      await until(() => guest.error != null);
      final rejected = guestTransport.sent.lastWhere(
        (m) => m.body['action'] == 'fire',
      );
      await submit(room, host, 'fire', {'cell': 0});
      final accepted = hostTransport.sent.lastWhere(
        (m) => m.body['action'] == 'fire',
      );
      var old = room.seq;
      guestTransport.send(rejected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(room.seq, old);
      expect(room.session.view(BattleshipSeat.player1).shots.length, 1);
      await submit(room, guest, 'fire', {'cell': 1});
      old = room.seq;
      hostTransport.send(accepted);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(room.seq, old);
      expect(host.view!.shots.length, 2);
      await submit(room, host, 'resign');
      await until(() => host.seq == room.seq && guest.seq == room.seq);
      host.send('rematch');
      guest.send('rematch');
      await until(() => host.round == 1 && guest.round == 1);
      expect(host.view!.phase, BattleshipPhase.placement);
      expect(host.view!.turn, BattleshipSeat.player2);
      expect(host.view!.ownFleet, isEmpty);
      expect(guest.view!.shots, isEmpty);
      await until(() => host.seq == room.seq && guest.seq == room.seq);
      host.send('randomize');
      guest.send('randomize');
      await until(
        () =>
            host.view!.ownFleet.length == 5 && guest.view!.ownFleet.length == 5,
      );
      await until(() => host.seq == room.seq && guest.seq == room.seq);
      host.send('ready');
      guest.send('ready');
      await until(() => room.session.phase == BattleshipPhase.playing);
      old = room.seq;
      hostTransport.send(accepted);
      guestTransport.send(rejected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(room.seq, old);
      expect(room.session.view(BattleshipSeat.player1).shots, isEmpty);
      // A new request identifier with an old round is rejected too.
      final stale = battleshipPayload(rejected)..['requestId'] = 100;
      guestTransport.send(battleshipMessage('fire', room.seq + 1, stale));
      await until(() => guest.error != null);
      expect(room.seq, old);
      expect(guest.view!.shots, isEmpty);
    },
  );

  test(
    'malformed recipient snapshot is atomic and keeps its last valid view',
    () async {
      final replica = BattleshipReplica();
      final (server, client) = MemoryTransport.pair();
      final roomId = battleshipSecret();
      final state = BattleshipSession();
      final subscription = server.messages.listen((message) {
        if (message.body['action'] != 'hello') return;
        server.send(
          battleshipMessage('welcome', 1, {
            'roomId': roomId,
            'seat': 0,
            'resume': battleshipSecret(),
            'lastRequest': 0,
          }),
        );
        server.send(
          battleshipMessage('snapshot', 1, {
            'roomId': roomId,
            'started': true,
            'round': 0,
            'view': state.view(BattleshipSeat.player1).toWire(),
            'seats': [
              {'occupied': true, 'connected': true},
              {'occupied': true, 'connected': true},
            ],
            'rematch': <int>[],
          }),
        );
      });
      addTearDown(() async {
        await subscription.cancel();
        await replica.close();
        await server.close();
      });
      await replica.bind(client, token: '1234');
      final previous = replica.view;
      final badView = Map<String, Object?>.of(previous!.toWire())
        ..['enemyFleet'] = [
          ShipPlacement(ShipType.carrier, 0, ShipDirection.horizontal).toWire(),
        ];
      server.send(
        battleshipMessage('snapshot', 2, {
          'roomId': roomId,
          'started': true,
          'round': 1,
          'view': badView,
          'seats': [
            {'occupied': true, 'connected': true},
            {'occupied': true, 'connected': true},
          ],
          'rematch': [1],
        }),
      );
      await until(() => replica.error != null);
      expect(replica.connected, isFalse);
      expect(identical(replica.view, previous), isTrue);
      expect(replica.seq, 1);
      expect(replica.round, 0);
      expect(replica.rematch, isEmpty);
    },
  );
}
