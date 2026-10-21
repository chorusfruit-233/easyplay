import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:easyplay/battleship/battleship.dart';
import 'package:easyplay/battleship/multiplayer/battleship_lan.dart';
import 'package:easyplay/battleship/multiplayer/battleship_protocol.dart';
import 'package:easyplay/battleship/multiplayer/battleship_replica.dart';
import 'package:easyplay/battleship/multiplayer/battleship_room_coordinator.dart';
import 'package:easyplay/lan/lan_protocol.dart' show lanProtocolVersion;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'network_test_support.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real socket complete match exposes only recipient fleet and reconnects same seat',
    () async {
      final room = BattleshipRoomCoordinator(
        password: '1942',
        session: BattleshipSession(random: Random(42)),
      );
      final server = BattleshipLanServer(room);
      await server.start(host: '127.0.0.1', port: 0);
      final (host, _) = await join(room, host: true);
      final guest = BattleshipReplica();
      final wires = <String>[];
      guest.onWireMessage = wires.add;
      addTearDown(() async {
        await host.close();
        await guest.close();
        await server.close();
        await room.close();
      });
      final uri = Uri.parse('ws://127.0.0.1:${server.port}');
      await guest.bind(await connectBattleshipSocket(uri), token: '1942');
      final http = _RealHttp().createHttpClient(null);
      final response = await (await http.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/easyplay/probe'),
      )).close();
      final probe =
          jsonDecode(await response.transform(utf8.decoder).join()) as Map;
      http.close();
      expect(probe, {
        'app': 'easyplay',
        'version': lanProtocolVersion,
        'game': 'battleship',
        'rulesVersion': 1,
        'protocolVersion': 1,
        'players': 2,
        'maxPlayers': 2,
        'phase': 'placement',
      });
      await begin(room, host, guest);
      await submit(room, host, 'fire', {'cell': 0});
      await submit(room, guest, 'fire', {'cell': 1});
      final ownFleet = guest.view!.ownFleet.toList();
      final shots = jsonEncode(
        guest.view!.shots.map((s) => s.toWire()).toList(),
      );
      await guest.disconnect();
      await until(() => !room.allConnected);
      await guest.bind(await connectBattleshipSocket(uri), token: '1942');
      expect(guest.view!.ownFleet, ownFleet);
      expect(
        jsonEncode(guest.view!.shots.map((s) => s.toWire()).toList()),
        shots,
      );
      // These agents receive only their own view; the authority's enemy fleet
      // never informs target selection.
      final ai = BattleshipAi(random: Random(5));
      for (
        var count = 0;
        count < 198 && room.session.phase != BattleshipPhase.finished;
        count++
      ) {
        final player = room.session.turn == BattleshipSeat.player1
            ? host
            : guest;
        await until(() => player.seq == room.seq);
        await submit(room, player, 'fire', {'cell': ai.choose(player.view!)});
      }
      await until(() => guest.view!.phase == BattleshipPhase.finished);
      expect(room.session.phase, BattleshipPhase.finished);
      expect(guest.view!.enemyFleet.length, 5);
      expect(
        guest.view!.shots.where((s) => s.outcome != ShotOutcome.miss).length,
        greaterThanOrEqualTo(17),
      );
      var privateSnapshots = 0;
      for (final raw in wires) {
        final message = LanMessage.decode(raw);
        if (message.body['action'] != 'snapshot') continue;
        final payload = battleshipPayload(message);
        final wireView = Map<String, Object?>.from(payload['view'] as Map);
        final view = BattleshipPlayerView.fromWire(wireView);
        expect(view.seat, BattleshipSeat.player2);
        expect(
          payload.keys,
          unorderedEquals([
            'roomId',
            'started',
            'round',
            'view',
            'seats',
            'rematch',
          ]),
        );
        expect(
          wireView.keys,
          unorderedEquals([
            'seat',
            'phase',
            'turn',
            'winner',
            'ready',
            'ownFleet',
            'enemyFleet',
            'shots',
          ]),
        );
        if (view.phase != BattleshipPhase.finished) {
          privateSnapshots++;
          expect(view.enemyFleet, isEmpty);
          expect(wireView['enemyFleet'], isEmpty);
        }
        expect(payload.containsKey('seed'), isFalse);
        expect(payload.containsKey('session'), isFalse);
        expect(payload.containsKey('fleets'), isFalse);
      }
      expect(privateSnapshots, greaterThan(20));
      await until(() => host.seq == room.seq && guest.seq == room.seq);
      host.send('rematch');
      guest.send('rematch');
      await until(() => host.round == 1 && guest.round == 1);
      expect(guest.view!.shots, isEmpty);
      expect(guest.view!.enemyFleet, isEmpty);
      expect(guest.view!.turn, BattleshipSeat.player2);
    },
  );

  test(
    'bundled quick join assets keep isolation headers and reject unsafe paths',
    () async {
      final room = BattleshipRoomCoordinator(password: '1234');
      final server = BattleshipLanServer(room);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        final path = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        if (path == 'assets/web/index.html') {
          return ByteData.sublistView(utf8.encode('<!doctype html>EasyPlay'));
        }
        return null;
      });
      await server.start(host: '127.0.0.1', port: 0);
      final client = _RealHttp().createHttpClient(null);
      addTearDown(() async {
        client.close(force: true);
        messenger.setMockMessageHandler('flutter/assets', null);
        await server.close();
        await room.close();
      });
      final origin = Uri.parse('http://127.0.0.1:${server.port}');
      final response = await (await client.getUrl(origin)).close();
      expect(response.statusCode, HttpStatus.ok);
      expect(
        response.headers.value('Cross-Origin-Opener-Policy'),
        'same-origin',
      );
      expect(
        response.headers.value('Cross-Origin-Embedder-Policy'),
        'require-corp',
      );
      expect(response.headers.value('Cache-Control'), 'no-cache');
      expect(
        await response.transform(utf8.decoder).join(),
        '<!doctype html>EasyPlay',
      );
      for (final path in [
        '/missing.js',
        '/assets//secret',
        '/assets/%2e%2e/private',
        '/assets/%5cprivate',
      ]) {
        final response = await (await client.getUrl(
          origin.replace(path: path),
        )).close();
        expect(
          response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.notFound),
        );
        await response.drain<void>();
      }
      final post = await (await client.postUrl(origin)).close();
      expect(post.statusCode, HttpStatus.methodNotAllowed);
      await post.drain<void>();
    },
  );
}
