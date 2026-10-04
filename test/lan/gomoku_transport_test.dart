import 'dart:async';
import 'dart:convert';

import 'package:easyplay/game_session.dart';
import 'package:easyplay/gomoku/gomoku_variant.dart';
import 'package:easyplay/lan/gomoku_lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_quick_join.dart';
import 'package:easyplay/lan/lan_scanner.dart';
import 'package:easyplay/lan/lan_transport.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'package:easyplay/lan/room_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = <String, Object?>{
  'game': 'gomoku',
  'rulesVersion': 2,
  'boardSize': 15,
  'variant': 'freestyle',
};

void main() {
  test(
    'Gomoku handshake and state sync require the supported rules and size',
    () {
      for (final type in [LanMessageType.hello, LanMessageType.stateSync]) {
        Map<String, Object?> payload(Map<String, Object?> config) => {
          ...config,
          'roomVersion': lanProtocolVersion,
          if (type == LanMessageType.hello) 'token': 'pin',
          if (type == LanMessageType.stateSync) 'events': <Object?>[],
        };
        for (final variant in GomokuVariant.values) {
          final config = {..._config, 'variant': variant.name};
          expect(
            LanMessage(type, 0, payload(config)).body['variant'],
            variant.name,
          );
          expect(LanMessage.parseGomokuVariant(config), variant);
        }
        for (final entry in <String, List<Object?>>{
          'rulesVersion': [null, 1, 3, '2', 2.0],
          'boardSize': [null, 9, 19, '15', 15.0],
          'variant': [null, 'unknown', 'Freestyle', 7],
        }.entries) {
          final field = entry.key;
          for (final value in entry.value) {
            expect(
              () => LanMessage(type, 0, payload({..._config, field: value})),
              throwsFormatException,
              reason: '$type must reject $field=$value',
            );
          }
        }
      }
      final coordinator = RoomCoordinator(
        gomokuAuthority: GomokuLanAuthority(),
        token: 'pin',
      );
      expect(coordinator.firstSide, Side.black);
      expect(coordinator.acceptsHello(_config), isTrue);
      expect(coordinator.acceptsHello({'game': 'go'}), isFalse);
      expect(coordinator.acceptsHello({..._config, 'boardSize': 19}), isFalse);
      expect(
        coordinator.acceptsHello({..._config, 'rulesVersion': 1}),
        isFalse,
      );
      expect(
        coordinator.acceptsHello({..._config, 'variant': 'standard'}),
        isFalse,
      );
      expect(coordinator.seq, 0);
      expect(coordinator.gameOver, isFalse);
    },
  );

  test(
    'quick join recognizes Gomoku and hides unsupported rule probes',
    () async {
      final origin = Uri.parse('http://192.168.1.20:8091/');
      for (final config in [
        for (final variant in GomokuVariant.values)
          {..._config, 'variant': variant.name},
        {..._config, 'boardSize': 19},
        {..._config, 'rulesVersion': 1},
        {..._config, 'variant': 'unknown'},
        {..._config, 'variant': null},
      ]) {
        final client = MockClient((request) async {
          expect(request.url, origin.resolve('/easyplay/probe'));
          return http.Response(
            jsonEncode({
              'app': 'easyplay',
              'version': lanProtocolVersion,
              ...config,
            }),
            200,
          );
        });
        final room = await LanWebRoom.probe(origin, client: client);
        final valid =
            config['boardSize'] == 15 &&
            config['rulesVersion'] == 2 &&
            GomokuVariant.values.any((v) => v.name == config['variant']);
        if (valid) {
          expect(room!.game, 'gomoku');
          expect(room.gomokuVariant.name, config['variant']);
          expect(room.label, '五子棋 · ${room.gomokuVariant.label}');
          expect(room.origin.port, 8091);
        } else {
          expect(room, isNull);
        }
        client.close();
      }
    },
  );

  testWidgets('Gomoku quick join still requires a nonempty room token', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LanQuickJoinPage(
          room: LanWebRoom(Uri.parse('http://host:8091'), 'gomoku', null),
        ),
      ),
    );
    final join = find.widgetWithText(FilledButton, '加入');
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<FilledButton>(join).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(join).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.pump();
    expect(tester.widget<FilledButton>(join).onPressed, isNotNull);
  });

  test(
    'Gomoku socket discovery, start gate, rejected actions and reconnect',
    () async {
      final authority = GomokuLanAuthority();
      final server = LanHostServer(gomokuAuthority: authority, token: 'pin');
      await server.start(host: '127.0.0.1', port: 0);
      final host = LanClientConnection.gomoku();
      final guest = LanClientConnection.gomoku();
      final wrongGame = LanClientConnection(const GoConfig());
      final wrongToken = LanClientConnection.gomoku();
      final uri = Uri.parse('ws://127.0.0.1:${server.port}');
      try {
        final found = await scanLanTargets(['127.0.0.1'], port: server.port!);
        expect(found.single.game, 'gomoku');
        expect(server.boardSize, 15);
        await expectLater(
          wrongGame.connect(uri, token: 'pin'),
          throwsStateError,
        );
        await expectLater(
          wrongToken.connect(uri, token: 'wrong'),
          throwsStateError,
        );
        await host.connect(uri, token: 'pin');
        await guest.connect(uri, token: 'pin');
        expect(host.side, Side.black);
        expect(guest.side, Side.white);
        expect(host.gomokuReplica, isNotNull);
        expect(host.replica, isNull);
        expect(guest.started, isFalse);
        final early = host.messages.firstWhere(
          (m) => m.type == LanMessageType.rejected,
        );
        host.send(
          LanMessage(LanMessageType.move, 1, {
            'side': 'B',
            'cell': [7, 7],
          }),
        );
        expect((await early).body['reason'], contains('等待'));
        final started = guest.messages.firstWhere(
          (m) => m.type == LanMessageType.matchStart,
        );
        server.startMatch();
        await started;
        final moved = guest.messages.firstWhere(
          (m) => m.type == LanMessageType.move,
        );
        host.send(
          LanMessage(LanMessageType.move, 1, {
            'side': 'B',
            'cell': [7, 7],
          }),
        );
        await moved;
        expect(host.seq, 1);
        expect(guest.seq, 1);
        expect(
          guest.gomokuReplica!.session.pieceAt(const Cell(7, 7)),
          Side.black,
        );
        for (final invalid in [
          LanMessage(LanMessageType.pass, 2, {'side': 'W'}),
          LanMessage(LanMessageType.drawRequest, 2, {'side': 'W'}),
          LanMessage(LanMessageType.move, 2, {
            'side': 'W',
            'cell': [15, 0],
          }),
          LanMessage(LanMessageType.move, 2, {
            'side': 'W',
            'cell': [7, 7],
          }),
          LanMessage(LanMessageType.resign, 2, {'side': 'B'}),
        ]) {
          final rejected = guest.messages.firstWhere(
            (m) => m.type == LanMessageType.rejected,
          );
          guest.send(invalid);
          await rejected;
          expect(server.seq, 1);
          expect(server.gameOver, isFalse);
        }
        final gone = server.playerCounts.firstWhere((n) => n == 1);
        await guest.disconnect();
        await gone;
        await guest.reconnect();
        expect(guest.side, Side.white);
        expect(guest.started, isTrue);
        expect(
          guest.gomokuReplica!.session.toJson(),
          authority.session.toJson(),
        );
        final request = guest.messages.firstWhere(
          (m) => m.type == LanMessageType.undoRequest,
        );
        host.send(LanMessage(LanMessageType.undoRequest, 2, {'side': 'B'}));
        await request;
        final accepted = guest.messages.firstWhere(
          (m) => m.type == LanMessageType.undoAccept,
        );
        guest.send(
          LanMessage(LanMessageType.undoAccept, 3, {
            'side': 'W',
            'requestSeq': 2,
          }),
        );
        await accepted;
        expect(authority.session.moves, isEmpty);
        expect(host.gomokuReplica!.session.moves, isEmpty);
        expect(guest.seq, 3);
      } finally {
        await wrongGame.close();
        await wrongToken.close();
        await guest.close();
        await host.close();
        await server.close();
      }
    },
  );

  for (final variant in GomokuVariant.values) {
    test(
      '${variant.name}: discovery and handshake keep the selected rule',
      () async {
        final authority = GomokuLanAuthority(variant: variant);
        final server = LanHostServer(gomokuAuthority: authority, token: 'pin');
        await server.start(host: '127.0.0.1', port: 0);
        final client = LanClientConnection.gomoku(variant: variant);
        final other = GomokuVariant.values.firstWhere((v) => v != variant);
        final wrong = LanClientConnection.gomoku(variant: other);
        final uri = Uri.parse('ws://127.0.0.1:${server.port}');
        try {
          final found = await scanLanTargets(['127.0.0.1'], port: server.port!);
          expect(found.single.variant, variant.name);
          await expectLater(wrong.connect(uri, token: 'pin'), throwsStateError);
          expect(server.playerCount, 0);
          await client.connect(uri, token: 'pin');
          expect(client.gomokuVariant, variant);
          expect(client.gomokuReplica!.variant, variant);
          expect(client.gomokuReplica!.session.variant, variant);
          expect(server.playerCount, 1);
        } finally {
          await wrong.close();
          await client.close();
          await server.close();
        }
      },
    );
  }

  testWidgets(
    'coordinator broadcasts committed Gomoku undo and rematch timeouts',
    (tester) async {
      final authority = GomokuLanAuthority();
      final coordinator = RoomCoordinator(
        gomokuAuthority: authority,
        token: 'pin',
      );
      final black = GomokuLanReplica();
      final white = GomokuLanReplica();
      final host = _TestPeer(black);
      final guest = _TestPeer(white);
      coordinator.attach(host);
      coordinator.attach(guest);
      host.request(
        LanMessage(LanMessageType.hello, 0, {
          ..._config,
          'roomVersion': lanProtocolVersion,
          'token': 'pin',
        }),
      );
      guest.request(
        LanMessage(LanMessageType.hello, 0, {
          ..._config,
          'roomVersion': lanProtocolVersion,
          'token': 'pin',
        }),
      );
      try {
        coordinator.startMatch();
        host.request(
          LanMessage(LanMessageType.move, 1, {
            'side': 'B',
            'cell': [7, 7],
          }),
        );
        host.request(LanMessage(LanMessageType.undoRequest, 2, {'side': 'B'}));
        expect(white.undoRequest, isNotNull);
        await tester.pump(const Duration(seconds: 30));
        expect(black.seq, 3);
        expect(white.seq, 3);
        expect(white.undoRequest, isNull);
        expect(white.session.moves, hasLength(1));
        guest.request(LanMessage(LanMessageType.resign, 4, {'side': 'W'}));
        host.request(
          LanMessage(LanMessageType.rematchRequest, 5, {'side': 'B'}),
        );
        expect(white.rematchRequest, isNotNull);
        await tester.pump(const Duration(seconds: 30));
        expect(black.seq, 6);
        expect(white.seq, 6);
        expect(white.rematchRequest, isNull);
        expect(white.session.gameOver, isTrue);
        expect(black.session.toJson(), white.session.toJson());
      } finally {
        await tester.runAsync(coordinator.close);
      }
    },
  );
}

// Synchronous delivery isolates negotiation deadlines from asynchronous socket
// scheduling, while answering heartbeats as real clients do.
class _TestPeer implements MessageTransport {
  _TestPeer(this.replica);
  final GomokuLanReplica replica;
  final _incoming = StreamController<LanMessage>.broadcast(sync: true);
  final _disconnects = StreamController<void>.broadcast(sync: true);
  @override
  Stream<LanMessage> get messages => _incoming.stream;
  @override
  Stream<void> get disconnections => _disconnects.stream;
  void request(LanMessage message) => _incoming.add(message);
  @override
  void send(LanMessage message) {
    if (message.type == LanMessageType.ping) {
      request(
        LanMessage(LanMessageType.pong, replica.seq, {
          'nonce': message.body['nonce'],
        }),
      );
    } else if (message.type == LanMessageType.stateSync ||
        LanMessage.eventTypes.contains(message.type)) {
      expectSync(replica.receive(message), isTrue);
    }
  }

  @override
  Future<void> close() async {
    await _incoming.close();
    await _disconnects.close();
  }
}
