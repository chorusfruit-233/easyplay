import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'package:easyplay/doudizhu/doudizhu.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_coordinator.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_protocol.dart';
import 'package:easyplay/doudizhu/multiplayer/doudizhu_replica.dart';
import 'test_support.dart';
import '../support/drop_first_hello.dart';

void main() {
  test('local host keeps its ready seat after the lobby is suspended', () {
    fakeAsync((time) {
      final room = CardRoomCoordinator(password: 'room-pin');
      final host = DouDizhuReplica();
      final (authority, client) = MemoryTransport.pair();
      room.attach(authority, fixedSeat: PlayerSeat.seat0);
      var pings = 0;
      host.onWireMessage = (raw) {
        if (LanMessage.decode(raw).body['action'] == 'ping') pings++;
      };
      host.bind(client, token: room.hostCredential);
      time.flushMicrotasks();
      host.send('ready');
      time.flushMicrotasks();
      time.elapseBlocking(const Duration(minutes: 5));
      time.elapse(const Duration(seconds: 5));
      expect(pings, 0);
      expect(host.connected, isTrue);
      expect(room.seats[0]['connected'], isTrue);
      expect(room.seats[0]['ready'], isTrue);
      final guests = <DouDizhuReplica>[];
      for (var i = 0; i < 2; i++) {
        final guest = DouDizhuReplica();
        final (remote, endpoint) = MemoryTransport.pair();
        room.attach(remote);
        guest.bind(endpoint, token: room.password);
        time.flushMicrotasks();
        guest.send('ready');
        time.flushMicrotasks();
        guests.add(guest);
      }
      expect(room.canStart, isTrue);
      host.send('start');
      time.flushMicrotasks();
      expect(host.view!.publicState.phase, DouDizhuPhase.bidding);
      host.close();
      for (final guest in guests) {
        guest.close();
      }
      room.close();
      time.flushMicrotasks();
      expect(time.pendingTimers, isEmpty);
    });
  });

  test(
    'negotiated HELLO retry recovers loss and duplicates preserve seat/seq',
    () async {
      final room = CardRoomCoordinator(password: 'retry-room');
      final client = DouDizhuReplica();
      addTearDown(() async {
        await client.close();
        await room.close();
      });
      final (server, endpoint) = MemoryTransport.pair();
      final transport = DropFirstHelloTransport(endpoint);
      final incoming = <LanMessage>[];
      client.onWireMessage = (raw) => incoming.add(LanMessage.decode(raw));
      room.attach(server, fixedSeat: PlayerSeat.seat1);
      await client.bind(transport, token: room.password);
      expect(transport.attempts, 2);
      expect(client.connected, isTrue);
      expect(client.view!.seat, PlayerSeat.seat1);
      final seq = room.seq;
      transport.inner.send(transport.hello!);
      await until(
        () => incoming.where((m) => m.body['action'] == 'welcome').length == 2,
      );
      expect(room.seq, seq);
      expect(room.playerCount, 1);
      expect(client.error, isNull);
      transport.inner.send(
        cardMessage('hello', 0, {'token': 'other-identity'}),
      );
      await until(() => client.error != null);
      expect(client.error, contains('身份已经绑定'));
      expect(room.seq, seq);
      expect(client.view!.seat, PlayerSeat.seat1);
    },
  );

  test(
    'three authenticated recipients only receive their own serialized hand',
    () async {
      final room = CardRoomCoordinator(
        password: 'test-room',
        session: DouDizhuSession(random: Random(1)),
      );
      final clients = <DouDizhuReplica>[], recordings = <RecordingTransport>[];
      addTearDown(() async {
        for (final c in clients) {
          await c.close();
        }
        await room.close();
      });
      for (final s in PlayerSeat.values) {
        final (c, r) = await join(room, s);
        clients.add(c);
        recordings.add(r);
      }
      await until(() => clients.every((c) => c.seq == room.seq));
      clients[0].send('start');
      await until(
        () => clients.every(
          (c) => c.view!.publicState.phase == DouDizhuPhase.bidding,
        ),
      );
      expect(room.playerCount, 3);
      for (final s in PlayerSeat.values) {
        for (final raw in recordings[s.index].sent) {
          final m = LanMessage.decode(raw);
          expect(m.type, LanMessageType.card);
          if (m.body['action'] != 'snapshot') continue;
          final payload = cardPayload(m);
          expect(
            payload.keys,
            unorderedEquals(['roomId', 'view', 'seats', 'rematch']),
          );
          final v = DouDizhuPlayerView.fromWire(
            Map<String, Object?>.from(payload['view'] as Map),
          );
          expect(v.seat, s);
          expect(v.publicState.bottom, isEmpty);
          if (v.publicState.phase == DouDizhuPhase.bidding) {
            expect(v.hand, room.session.view(s).hand);
            for (final other in PlayerSeat.values.where((o) => o != s)) {
              expect(
                v.hand.toSet().intersection(
                  room.session.view(other).hand.toSet(),
                ),
                isEmpty,
              );
            }
          }
          expect(jsonEncode(payload).contains('seed'), isFalse);
          expect(jsonEncode(payload).contains('events'), isFalse);
        }
      }
      final turn = room.session.turn;
      clients[turn.index].send('bid', {'score': 3});
      await until(
        () => clients.every(
          (c) => c.view!.publicState.phase == DouDizhuPhase.playing,
        ),
      );
      final seq = room.seq, own = clients[turn.index].view!.hand.toList();
      clients[turn.index].send('play', {
        'cards': [own.first, own.first],
      });
      await until(() => clients[turn.index].error != null);
      expect(room.seq, seq);
      expect(room.session.view(turn).hand, own);
      clients[turn.next.index].send('play', {
        'cards': [clients[turn.next.index].view!.hand.first],
      });
      await until(() => clients[turn.next.index].error != null);
      expect(room.seq, seq);
      clients[turn.index].send('play', {
        'cards': [own.first],
      });
      await until(() => room.seq == seq + 1);
      expect(room.session.view(turn).hand.length, 19);
    },
  );
  test(
    'resume authenticates seat and atomically replaces private snapshot',
    () async {
      final room = CardRoomCoordinator(password: 'password');
      final host = (await join(room, PlayerSeat.seat0)).$1;
      final guest = (await join(room, PlayerSeat.seat1)).$1;
      final third = (await join(room, PlayerSeat.seat2)).$1;
      addTearDown(() async {
        await host.close();
        await guest.close();
        await third.close();
        await room.close();
      });
      await until(() => host.seq == room.seq);
      host.send('start');
      await until(() => guest.view!.publicState.phase == DouDizhuPhase.bidding);
      host.send('bid', {'score': 3});
      await until(() => guest.view!.publicState.phase == DouDizhuPhase.playing);
      host.send('play', {
        'cards': [host.view!.hand.first],
      });
      await until(() => guest.view!.publicState.played.length == 1);
      final hand = guest.view!.hand.toList();
      await guest.disconnect();
      await until(() => !room.allConnected);
      final (server, client) = MemoryTransport.pair();
      room.attach(server);
      await guest.bind(client, token: 'password');
      expect(guest.view!.hand, hand);
      expect(guest.seq, room.seq);
      expect(room.allConnected, isTrue);
      expect(third.connected, isTrue);
      final impostor = DouDizhuReplica();
      final (a, b) = MemoryTransport.pair();
      room.attach(a);
      await expectLater(impostor.bind(b, token: 'password'), throwsStateError);
      await impostor.close();
      expect(room.session.view(PlayerSeat.seat1).hand, hand);
    },
  );
  test(
    'cross-room credentials, stale seq, forged seat and unready start reject',
    () async {
      final room = CardRoomCoordinator(password: 'p');
      final host = (await join(room, PlayerSeat.seat0)).$1;
      addTearDown(() async {
        await host.close();
        await room.close();
      });
      host.send('start');
      await until(() => host.error != null);
      expect(room.session.phase, DouDizhuPhase.waiting);
      final (server, client) = MemoryTransport.pair();
      room.attach(server);
      final responses = <LanMessage>[];
      final sub = client.messages.listen(responses.add);
      client.send(
        cardMessage('hello', 0, {
          'token': 'p',
          'resume': cardSecret(),
          'roomId': 'wrong-room',
        }),
      );
      await until(() => responses.isNotEmpty);
      expect(responses.last.body['action'], 'rejected');
      expect(room.playerCount, 1);
      await sub.cancel();
      await client.close();
      room.setAi(PlayerSeat.seat1, true);
      room.setAi(PlayerSeat.seat2, true);
      await until(() => host.seq == room.seq);
      host.send('start');
      await until(() => host.view!.publicState.phase == DouDizhuPhase.bidding);
      host.send('bid', {'score': 3, 'seat': 2});
      await until(() => host.view!.publicState.phase == DouDizhuPhase.playing);
      expect(room.session.landlord, PlayerSeat.seat0);
    },
  );
  test(
    'two humans plus AI finishes, rematch preserves seq and identities',
    () async {
      final room = CardRoomCoordinator(
        password: 'p',
        session: DouDizhuSession(random: Random(5)),
      );
      room.setAi(PlayerSeat.seat2, true);
      final host = (await join(room, PlayerSeat.seat0)).$1;
      final guest = (await join(room, PlayerSeat.seat1)).$1;
      addTearDown(() async {
        await host.close();
        await guest.close();
        await room.close();
      });
      await until(() => host.seq == room.seq);
      host.send('start');
      await until(() => room.session.phase == DouDizhuPhase.bidding);
      host.send('bid', {'score': 3});
      await until(() => room.session.phase == DouDizhuPhase.playing);
      for (
        var moves = 0;
        moves < 300 && room.session.phase != DouDizhuPhase.finished;
        moves++
      ) {
        await until(
          () =>
              room.session.turn != PlayerSeat.seat2 ||
              room.session.phase == DouDizhuPhase.finished,
        );
        if (room.session.phase == DouDizhuPhase.finished) break;
        final c = room.session.turn == PlayerSeat.seat0 ? host : guest;
        await until(() => c.seq == room.seq);
        final old = room.seq, ids = const DouDizhuAi().choosePlay(c.view!);
        c.send(ids.isEmpty ? 'pass' : 'play', {'cards': ids});
        await until(() => room.seq > old);
      }
      expect(room.session.phase, DouDizhuPhase.finished);
      await until(() => host.seq == room.seq);
      final oldSeq = room.seq, roomId = host.roomId;
      host.send('rematch');
      await until(() => room.seq > oldSeq);
      await until(() => guest.seq == room.seq);
      guest.send('rematch');
      await until(() => host.view!.publicState.phase == DouDizhuPhase.bidding);
      expect(host.seq, greaterThan(oldSeq));
      expect(host.roomId, roomId);
      expect(host.view!.publicState.played, isEmpty);
      expect(host.view!.publicState.bottom, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
