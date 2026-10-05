import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/doudizhu/doudizhu.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_coordinator.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_protocol.dart';
import 'package:easyplay/doudizhu/multiplayer/card_rtc_room.dart';
import 'package:easyplay/doudizhu/multiplayer/doudizhu_replica.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'test_support.dart';

void main() {
  test('host readiness completes before configuring mixed AI seats', () async {
    final room = CardRtcRoom.host(iceServers: []);
    addTearDown(room.close);
    await room.prepareHost();
    expect(room.coordinator!.seats[0]['ready'], true);
    room.coordinator!.setAi(PlayerSeat.seat1, true);
    room.coordinator!.setAi(PlayerSeat.seat2, true);
    await until(() => room.replica.seq == room.coordinator!.seq);
    expect(room.coordinator!.canStart, true);
    expect(room.replica.error, isNull);
  });

  test('stale and future ready requests cannot change room state', () async {
    final room = CardRoomCoordinator(password: 'p');
    final (server, client) = MemoryTransport.pair();
    final replica = DouDizhuReplica();
    room.attach(server, fixedSeat: PlayerSeat.seat0);
    await replica.bind(client, token: room.hostCredential);
    addTearDown(() async {
      await replica.close();
      await room.close();
    });
    final seq = room.seq;
    for (final requestSeq in [seq, seq + 2]) {
      replica.error = null;
      client.send(cardMessage('ready', requestSeq, {'roomId': room.roomId}));
      await until(() => replica.error != null);
      expect(room.seq, seq);
      expect(room.seats[0]['ready'], false);
    }
    replica.send('ready');
    await until(() => room.seats[0]['ready'] == true);
  });

  test(
    'host replaces only one RTC seat before disconnect events arrive',
    () async {
      final room = CardRoomCoordinator(password: 'p');
      final host = (await join(room, PlayerSeat.seat0)).$1;
      final guest = (await join(room, PlayerSeat.seat1)).$1;
      final third = (await join(room, PlayerSeat.seat2)).$1;
      addTearDown(() async {
        await host.close();
        await guest.close();
        await third.close();
        await room.close();
      });
      // Neither the remote disconnection event nor a timer releases this seat.
      final disconnecting = room.disconnectSeat(PlayerSeat.seat1);
      expect(room.seats[1]['connected'], false);
      expect(room.seats[2]['connected'], true);
      await disconnecting;
      final (server, client) = MemoryTransport.pair();
      room.attach(server, fixedSeat: PlayerSeat.seat1);
      await guest.bind(client, token: 'p');
      expect(room.allConnected, true);
      expect(third.connected, true);
    },
  );

  for (final badField in ['seats', 'rematch', 'view']) {
    test(
      'invalid $badField snapshot never partially commits private state',
      () async {
        final session = DouDizhuSession();
        final replica = DouDizhuReplica();
        final (server, client) = MemoryTransport.pair();
        final sub = server.messages.listen((_) {});
        addTearDown(() async {
          await replica.close();
          await sub.cancel();
          await server.close();
        });
        final binding = replica.bind(client, token: 'p');
        await Future<void>.delayed(Duration.zero);
        server.send(
          cardMessage('welcome', 0, {
            'roomId': 'room',
            'resume': 'credential',
            'seat': 0,
          }),
        );
        Map<String, Object?> snapshot() => {
          'roomId': 'room',
          'view': session.view(PlayerSeat.seat0).toWire(),
          'seats': List.generate(
            3,
            (_) => {
              'occupied': true,
              'connected': true,
              'ready': true,
              'ai': false,
            },
          ),
          'rematch': <int>[],
        };
        server.send(cardMessage('snapshot', 1, snapshot()));
        await binding;
        final previous = replica.view;
        session.deal();
        final invalid = snapshot();
        if (badField == 'seats') {
          invalid['seats'] = [
            {'occupied': true},
          ];
        }
        if (badField == 'rematch') invalid['rematch'] = [0, 0];
        if (badField == 'view') {
          invalid['view'] = session.view(PlayerSeat.seat1).toWire();
        }
        server.send(cardMessage('snapshot', 2, invalid));
        await until(() => replica.error != null);
        expect(replica.seq, 1);
        expect(identical(replica.view, previous), true);
        expect(replica.view!.hand, isEmpty);
      },
    );
  }

  test(
    'initial private snapshot must match the authenticated welcome seat',
    () async {
      final replica = DouDizhuReplica();
      final (server, client) = MemoryTransport.pair();
      final sub = server.messages.listen((_) {});
      addTearDown(() async {
        await replica.close();
        await sub.cancel();
        await server.close();
      });
      final binding = replica.bind(client, token: 'p');
      await Future<void>.delayed(Duration.zero);
      final rejected = expectLater(binding, throwsStateError);
      server.send(
        cardMessage('welcome', 0, {
          'roomId': 'room',
          'resume': 'credential',
          'seat': 0,
        }),
      );
      server.send(
        cardMessage('snapshot', 1, {
          'roomId': 'room',
          'view': DouDizhuSession().view(PlayerSeat.seat1).toWire(),
          'seats': [],
          'rematch': [],
        }),
      );
      await rejected;
      expect(replica.view, isNull);
      expect(replica.seq, 0);
    },
  );

  test(
    'public snapshot rejects invalid cards, bids and nonconserving counts',
    () {
      final session = DouDizhuSession()..deal();
      session.bid(session.turn, 3);
      for (final change in <void Function(Map<String, Object?>)>[
        (d) => d['bottom'] = [54, 1, 2],
        (d) => d['bottom'] = [0, 0, 1],
        (d) => d['bids'] = [4, null, null],
        (d) => d['counts'] = [19, 17, 17],
        (d) => d['winner'] = 'farmers',
      ]) {
        final data = Map<String, Object?>.from(
          jsonDecode(jsonEncode(session.publicState.toWire())) as Map,
        );
        change(data);
        expect(() => PublicGameState.fromWire(data), throwsFormatException);
      }
      expect(PublicGameState.fromWire(session.publicState.toWire()).counts, [
        20,
        17,
        17,
      ]);
    },
  );

  test('malformed invite scalar types produce a recoverable format error', () {
    final invite = CardRtcInvitation(
      roomId: cardSecret(),
      seat: PlayerSeat.seat1,
      sessionId: cardSecret(),
      token: cardSecret(),
      sdp: 'v=0\r\n',
      type: 'offer',
    );
    for (final field in ['seat', 'createdAt']) {
      final data = jsonDecode(invite.encode()) as Map<String, dynamic>;
      data[field] = field == 'seat' ? 1.0 : 42;
      expect(
        () => CardRtcInvitation.decode(jsonEncode(data), type: 'offer'),
        throwsFormatException,
      );
    }
  });
}
