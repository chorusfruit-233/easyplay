import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/doudizhu/doudizhu.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_coordinator.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_protocol.dart';
import 'package:easyplay/doudizhu/multiplayer/doudizhu_replica.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'test_support.dart';

void main() {
  test(
    'old seq, cross-room action and unowned card leave authority unchanged',
    () async {
      final room = CardRoomCoordinator(password: 'p');
      room.setAi(PlayerSeat.seat1, true);
      room.setAi(PlayerSeat.seat2, true);
      final (server, client) = MemoryTransport.pair();
      room.attach(server, fixedSeat: PlayerSeat.seat0);
      final replica = DouDizhuReplica();
      await replica.bind(client, token: room.hostCredential);
      addTearDown(() async {
        await replica.close();
        await room.close();
      });
      replica.send('ready');
      await until(() => room.canStart && replica.seq == room.seq);
      replica.send('start');
      await until(
        () => replica.view!.publicState.phase == DouDizhuPhase.bidding,
      );
      final seq = room.seq, hand = room.session.view(PlayerSeat.seat0).hand;
      client.send(cardMessage('bid', seq, {'roomId': room.roomId, 'score': 3}));
      await until(() => replica.error != null);
      expect(room.seq, seq);
      expect(room.session.phase, DouDizhuPhase.bidding);
      replica.error = null;
      client.send(
        cardMessage('bid', seq + 1, {'roomId': cardSecret(), 'score': 3}),
      );
      await until(() => replica.error != null);
      expect(room.seq, seq);
      expect(room.session.view(PlayerSeat.seat0).hand, hand);
      replica.send('bid', {'score': 3});
      await until(() => room.session.phase == DouDizhuPhase.playing);
      await until(() => replica.seq == room.seq);
      final playingSeq = room.seq;
      replica.send('play', {
        'cards': [room.session.view(PlayerSeat.seat1).hand.first],
      });
      await until(() => replica.error != null);
      expect(room.seq, playingSeq);
      expect(room.session.view(PlayerSeat.seat0).hand.length, 20);
    },
  );
  test(
    'seat-bound resume cannot replay online, cross rooms or onto another peer',
    () async {
      final room = CardRoomCoordinator(password: 'p');
      final host = (await join(room, PlayerSeat.seat0)).$1;
      final (guest, recording) = await join(room, PlayerSeat.seat1);
      final welcome = recording.sent
          .map(LanMessage.decode)
          .firstWhere((m) => m.body['action'] == 'welcome');
      final credential = cardPayload(welcome)['resume'];
      final strangerRoom = CardRoomCoordinator(password: 'p');
      addTearDown(() async {
        await guest.close();
        await host.close();
        await room.close();
        await strangerRoom.close();
      });
      Future<void> rejected(
        CardRoomCoordinator target,
        PlayerSeat? fixed,
        String id,
      ) async {
        final (server, client) = MemoryTransport.pair();
        target.attach(server, fixedSeat: fixed);
        final responses = <LanMessage>[];
        final sub = client.messages.listen(responses.add);
        client.send(
          cardMessage('hello', 0, {
            'token': 'p',
            'resume': credential,
            'roomId': id,
            'seat': 2,
          }),
        );
        await until(() => responses.isNotEmpty);
        expect(responses.first.body['action'], 'rejected');
        expect(cardPayload(responses.first).keys, unorderedEquals(['reason']));
        await sub.cancel();
        await client.close();
      }

      await rejected(
        room,
        null,
        room.roomId,
      ); // A connected seat cannot be displaced.
      await rejected(strangerRoom, null, strangerRoom.roomId);
      await guest.disconnect();
      await until(() => room.seats[1]['connected'] == false);
      await rejected(room, PlayerSeat.seat2, room.roomId);
      final (a, b) = MemoryTransport.pair();
      room.attach(a, fixedSeat: PlayerSeat.seat1);
      await guest.bind(b, token: 'p');
      expect(guest.view!.seat, PlayerSeat.seat1);
      expect(room.playerCount, 2);
    },
  );
  test(
    'closing during queued AI work cancels it and clears every private hand',
    () async {
      final room = CardRoomCoordinator(password: 'p');
      room.setAi(PlayerSeat.seat1, true);
      room.setAi(PlayerSeat.seat2, true);
      final host = (await join(room, PlayerSeat.seat0)).$1;
      await until(() => host.seq == room.seq);
      host.send('start');
      await until(() => host.view!.publicState.phase == DouDizhuPhase.bidding);
      host.send('bid', {'score': 0});
      await until(() => room.session.turn == PlayerSeat.seat1);
      await room.close();
      final seq = room.seq;
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(room.seq, seq);
      expect(room.session.publicState.counts, [0, 0, 0]);
      expect(room.session.publicState.bottom, isEmpty);
      await host.close();
    },
  );
}
