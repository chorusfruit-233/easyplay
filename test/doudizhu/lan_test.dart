import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/lan/lan_scanner.dart';
import 'package:easyplay/doudizhu/doudizhu.dart';
import 'package:easyplay/doudizhu/multiplayer/card_lan.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_protocol.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_coordinator.dart';
import 'package:easyplay/doudizhu/multiplayer/doudizhu_replica.dart';
import 'test_support.dart';

void main() {
  test(
    'real WebSocket three players, discovery, private wire data and reconnect',
    () async {
      final room = CardRoomCoordinator(password: 'friends');
      final server = CardLanServer(room);
      await server.start(host: '127.0.0.1', port: 0);
      final host = (await join(room, PlayerSeat.seat0)).$1;
      final guests = [DouDizhuReplica(), DouDizhuReplica()];
      final received = List.generate(2, (_) => <String>[]);
      final subscriptions = [];
      addTearDown(() async {
        for (final sub in subscriptions) {
          await sub.cancel();
        }
        await host.close();
        for (final g in guests) {
          await g.close();
        }
        await room.close();
        await server.close();
      });
      final uri = Uri.parse('ws://127.0.0.1:${server.port}');
      for (var i = 0; i < 2; i++) {
        final transport = await connectCardSocket(uri);
        subscriptions.add(
          transport.messages.listen((m) => received[i].add(m.encode())),
        );
        await guests[i].bind(transport, token: 'friends');
        guests[i].send('ready');
        await until(() => room.seats[i + 1]['ready'] == true);
      }
      final http = HttpClient();
      final response = await (await http.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/easyplay/probe'),
      )).close();
      final probe =
          jsonDecode(await response.transform(utf8.decoder).join()) as Map;
      http.close();
      expect(probe['game'], 'doudizhu');
      expect(probe['players'], 3);
      expect(probe['maxPlayers'], 3);
      expect(
        probe.keys,
        unorderedEquals([
          'app',
          'version',
          'game',
          'rulesVersion',
          'protocolVersion',
          'players',
          'maxPlayers',
          'phase',
        ]),
      );
      final found = await scanLanTargets(
        ['127.0.0.1'],
        port: server.port!,
        timeout: const Duration(seconds: 2),
      );
      expect(found.single.game, 'doudizhu');
      await until(() => host.seq == room.seq);
      host.send('start');
      await until(
        () => guests.every(
          (g) => g.view!.publicState.phase == DouDizhuPhase.bidding,
        ),
      );
      for (var i = 0; i < 2; i++) {
        for (final raw in received[i]) {
          final m = LanMessage.decode(raw);
          if (m.body['action'] != 'snapshot') continue;
          final payload = cardPayload(m);
          final v = DouDizhuPlayerView.fromWire(
            Map<String, Object?>.from(payload['view'] as Map),
          );
          if (v.publicState.phase == DouDizhuPhase.bidding) {
            expect(v.hand, room.session.view(PlayerSeat.values[i + 1]).hand);
            expect(v.publicState.bottom, isEmpty);
            expect(
              v.hand.toSet().intersection(
                room.session.view(PlayerSeat.seat0).hand.toSet(),
              ),
              isEmpty,
            );
          }
          expect(payload.containsKey('events'), isFalse);
          expect(payload.containsKey('seed'), isFalse);
        }
      }
      host.send('bid', {'score': 3});
      await until(
        () => guests[0].view!.publicState.phase == DouDizhuPhase.playing,
      );
      await until(() => host.seq == room.seq);
      host.send('play', {
        'cards': [host.view!.hand.first],
      });
      await until(
        () =>
            guests[0].seq == room.seq && room.session.turn == PlayerSeat.seat1,
      );
      guests[0].send('pass');
      await until(
        () =>
            guests[1].seq == room.seq && room.session.turn == PlayerSeat.seat2,
      );
      guests[1].send('pass');
      await until(
        () =>
            guests[0].seq == room.seq && room.session.turn == PlayerSeat.seat0,
      );
      final historyBefore = jsonEncode(
        guests[0].view!.publicState.toWire()['history'],
      );
      final before = guests[0].view!.hand.toList();
      await guests[0].disconnect();
      await until(() => !room.allConnected);
      await guests[0].bind(await connectCardSocket(uri), token: 'friends');
      expect(guests[0].view!.hand, before);
      expect(guests[0].seq, room.seq);
      expect(
        jsonEncode(guests[0].view!.publicState.toWire()['history']),
        historyBefore,
      );
      expect(guests[1].connected, isTrue);
      final all = [host, ...guests];
      for (
        var n = 0;
        n < 400 && room.session.phase != DouDizhuPhase.finished;
        n++
      ) {
        final c = all[room.session.turn.index];
        await until(() => c.seq == room.seq);
        final old = room.seq, play = const DouDizhuAi().choosePlay(c.view!);
        c.send(play.isEmpty ? 'pass' : 'play', {'cards': play});
        await until(() => room.seq > old);
      }
      expect(room.session.phase, DouDizhuPhase.finished);
      for (final c in all) {
        await until(() => c.seq == room.seq);
        final previous = room.seq;
        c.send('rematch');
        await until(() => room.seq > previous);
        await until(() => c.seq == room.seq);
      }
      await until(
        () => guests.every(
          (g) => g.view!.publicState.phase == DouDizhuPhase.bidding,
        ),
      );
      expect(room.session.validateConservation(), isTrue);
      expect(guests[0].view!.publicState.history, isEmpty);
    },
  );
  test('independent protocol rejects incompatible envelopes', () {
    expect(
      () => LanMessage.decode(
        jsonEncode({
          'type': 'card',
          'seq': 0,
          'game': 'doudizhu',
          'protocolVersion': 2,
          'rulesVersion': 1,
          'action': 'hello',
          'payload': {},
        }),
      ),
      throwsFormatException,
    );
  });
}
