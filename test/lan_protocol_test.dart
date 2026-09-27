import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:easyplay/game_session.dart';
import 'package:easyplay/lan/lan_game.dart';
import 'package:easyplay/lan/lan_ports.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_scanner.dart';
import 'package:easyplay/lan/lan_transport.dart';

void main() {
  test('wire messages round trip and reject malformed payloads', () {
    final message = LanMessage(LanMessageType.move, 1, {
      'side': 'B',
      'cell': [3, 3],
    });
    final restored = LanMessage.decode(message.encode());
    expect(restored.type, LanMessageType.move);
    expect(restored.side, Side.black);
    expect(LanMessage.parseCell(restored.body['cell']), const Cell(3, 3));
    expect(
      () => LanMessage.decode('{"type":"move","seq":1,"side":"B"}'),
      throwsFormatException,
    );
  });

  test('subnet enumeration excludes network and broadcast addresses', () {
    expect(LanSubnet.hosts('192.168.1.42', 24).first, '192.168.1.1');
    expect(LanSubnet.hosts('192.168.1.42', 24).last, '192.168.1.254');
    expect(LanSubnet.hosts('10.0.0.5', 30), ['10.0.0.5', '10.0.0.6']);
    expect(() => LanSubnet.hosts('10.0.0.1', 33), throwsArgumentError);
    final candidates = LanSubnet.candidates([
      (name: 'wlan0', address: '192.168.1.2'),
      (name: 'wlan1', address: '192.168.1.3'),
      (name: 'tun0', address: '10.8.0.3'),
    ]);
    expect(candidates, hasLength(254));
    expect(candidates, contains('192.168.1.254'));
    expect(candidates, isNot(contains('10.8.0.1')));
  });

  test(
    'probe recognizes only EasyPlay and finishes fixed scan quickly',
    () async {
      final room = LanHostServer(
        authority: LanAuthority(const GoConfig(boardSize: 9)),
        token: 'pin',
      );
      await room.start(host: '127.0.0.1', port: 0);
      try {
        final watch = Stopwatch()..start();
        final found = await scanLanTargets(
          ['127.0.0.1', '127.0.0.2'],
          port: room.port!,
          concurrency: 2,
        );
        expect(found.map((room) => room.host), ['127.0.0.1']);
        expect(watch.elapsed, lessThan(const Duration(milliseconds: 1500)));
      } finally {
        await room.close();
      }
      final other = await HttpServer.bind('127.0.0.1', 0);
      other.listen((request) async {
        request.response
          ..headers.contentType = ContentType.json
          ..write('{"app":"something-else"}');
        await request.response.close();
      });
      try {
        expect(await scanLanTargets(['127.0.0.1'], port: other.port), isEmpty);
      } finally {
        await other.close(force: true);
      }
    },
  );

  test(
    'host selects another port when the requested port is occupied',
    () async {
      final occupied = await HttpServer.bind('127.0.0.1', 0);
      final room = LanHostServer(
        authority: LanAuthority(const GoConfig(boardSize: 9)),
        token: 'pin',
      );
      try {
        await room.start(host: '127.0.0.1', port: occupied.port);
        expect(room.port, isNot(occupied.port));
        expect(room.port, greaterThan(0));
        final found = await scanLanTargets([
          '127.0.0.1',
        ], ports: lanDiscoveryPorts(occupied.port));
        expect(found.map((endpoint) => endpoint.port), contains(room.port));
      } finally {
        await room.close();
        await occupied.close(force: true);
      }
    },
  );

  test('guest waits until host starts and early moves are rejected', () async {
    const config = GoConfig(boardSize: 9);
    final room = LanHostServer(authority: LanAuthority(config), token: 'pin');
    await room.start(host: '127.0.0.1', port: 0);
    final host = LanClientConnection(config);
    final guest = LanClientConnection(config);
    try {
      final uri = Uri.parse('ws://127.0.0.1:${room.port}');
      await host.connect(uri, token: 'pin');
      await guest.connect(uri, token: 'pin');
      expect(host.started, isFalse);
      expect(guest.started, isFalse);
      final rejected = guest.messages.firstWhere(
        (message) => message.type == LanMessageType.rejected,
      );
      guest.send(
        LanMessage(LanMessageType.move, 1, {
          'side': 'W',
          'cell': [0, 0],
        }),
      );
      expect((await rejected).body['reason'], '等待房主开始对局');
      final started = guest.messages.firstWhere(
        (message) => message.type == LanMessageType.matchStart,
      );
      room.startMatch();
      await started;
      expect(room.started, isTrue);
      expect(guest.started, isTrue);
      expect(room.authority.seq, 0);
    } finally {
      await guest.close();
      await host.close();
      await room.close();
    }
  });

  test('authority validates turn, seq and side before changing state', () {
    final host = LanAuthority(const GoConfig(boardSize: 9));
    LanMessage move(int seq, String side, int row) =>
        LanMessage(LanMessageType.move, seq, {
          'side': side,
          'cell': [row, row],
        });
    expect(
      host.submit(Side.white, move(1, 'W', 0)).type,
      LanMessageType.rejected,
    );
    expect(host.seq, 0);
    expect(host.submit(Side.black, move(1, 'B', 0)).type, LanMessageType.move);
    expect(host.session.moves, hasLength(1));
    expect(
      host.submit(Side.black, move(2, 'B', 1)).type,
      LanMessageType.rejected,
    );
    expect(host.seq, 1);
    expect(host.submit(Side.white, move(2, 'W', 1)).type, LanMessageType.move);
    expect(host.session.moves, hasLength(2));
  });

  test('replica ignores duplicate or gap and converges after full sync', () {
    final config = const GoConfig(boardSize: 9);
    final host = LanAuthority(config);
    final replica = LanReplica(config);
    final first = host.submit(
      Side.black,
      LanMessage(LanMessageType.move, 1, {
        'side': 'B',
        'cell': [0, 0],
      }),
    );
    expect(replica.receive(first), isTrue);
    expect(replica.receive(first), isFalse);
    final gap = LanMessage(LanMessageType.move, 3, {
      'side': 'B',
      'cell': [1, 1],
    });
    expect(replica.receive(gap), isFalse);
    final second = host.submit(
      Side.white,
      LanMessage(LanMessageType.move, 2, {
        'side': 'W',
        'cell': [1, 1],
      }),
    );
    expect(replica.receive(second), isTrue);
    expect(replica.session.moves, hasLength(2));
    final sync = host.sync(replica.stateRequest());
    expect(replica.receive(sync), isTrue);
    expect(replica.session.moves, hasLength(2));
    expect(replica.sgf, host.sgf);
  });

  test(
    'undo requires opponent acceptance and score requires matching proposal',
    () {
      final host = LanAuthority(const GoConfig(boardSize: 9));
      LanMessage submit(
        Side side,
        LanMessageType type,
        int seq,
        Map<String, Object?> body,
      ) => host.submit(side, LanMessage(type, seq, body));
      submit(Side.black, LanMessageType.move, 1, {
        'side': 'B',
        'cell': [0, 0],
      });
      final request = submit(Side.white, LanMessageType.undoRequest, 2, {
        'side': 'W',
      });
      expect(request.type, LanMessageType.undoRequest);
      expect(host.session.moves, hasLength(1));
      final accept = submit(Side.black, LanMessageType.undoAccept, 3, {
        'side': 'B',
        'requestSeq': 2,
      });
      expect(accept.type, LanMessageType.undoAccept);
      expect(host.session.moves, isEmpty);
    },
  );

  test('both players must accept the same dead-stone proposal', () {
    final host = LanAuthority(const GoConfig(boardSize: 9));
    LanMessage submit(
      Side side,
      LanMessageType type,
      int seq,
      Map<String, Object?> body,
    ) => host.submit(side, LanMessage(type, seq, body));
    submit(Side.black, LanMessageType.move, 1, {
      'side': 'B',
      'cell': [0, 0],
    });
    submit(Side.white, LanMessageType.pass, 2, {'side': 'W'});
    submit(Side.black, LanMessageType.pass, 3, {'side': 'B'});
    final proposal = submit(Side.white, LanMessageType.scoreProposal, 4, {
      'side': 'W',
      'deadStones': <Object?>[],
    });
    expect(proposal.type, LanMessageType.scoreProposal);
    final mismatch = submit(Side.black, LanMessageType.scoreCounter, 5, {
      'side': 'B',
      'requestSeq': 4,
      'deadStones': [
        [0, 0],
      ],
    });
    expect(mismatch.type, LanMessageType.scoreCounter);
    expect(host.session.goScoreConfirmed, isFalse);
    final accept = submit(Side.white, LanMessageType.scoreAccept, 6, {
      'side': 'W',
      'requestSeq': 5,
    });
    expect(accept.type, LanMessageType.scoreAccept);
    expect(host.session.goScoreConfirmed, isTrue);
  });

  test('undo timeout is a committed rejection on both replicas', () {
    final config = const GoConfig(boardSize: 9);
    final host = LanAuthority(config);
    final black = LanReplica(config);
    final white = LanReplica(config);
    final move = host.submit(
      Side.black,
      LanMessage(LanMessageType.move, 1, {
        'side': 'B',
        'cell': [0, 0],
      }),
    );
    expect(black.receive(move), isTrue);
    expect(white.receive(move), isTrue);
    final request = host.submit(
      Side.white,
      LanMessage(LanMessageType.undoRequest, 2, {'side': 'W'}),
    );
    expect(black.receive(request), isTrue);
    expect(white.receive(request), isTrue);
    final expired = host.expireUndo(request.seq)!;
    expect(expired.type, LanMessageType.undoReject);
    expect(black.receive(expired), isTrue);
    expect(white.receive(expired), isTrue);
    expect(black.sgf, host.sgf);
    expect(white.sgf, host.sgf);
    expect(host.session.moves, hasLength(1));
  });

  test(
    'localhost transport performs probe, handshake and broadcasts moves',
    () async {
      final host = LanHostServer(
        authority: LanAuthority(const GoConfig(boardSize: 9)),
        token: 'test-token',
      );
      await host.start(host: '127.0.0.1', port: 0);
      final port = host.port!;
      final probe = await HttpClient().getUrl(
        Uri.parse('http://127.0.0.1:$port/easyplay/probe'),
      );
      final response = await probe.close();
      expect(response.statusCode, 200);
      expect(
        await response.transform(const Utf8Decoder()).join(),
        contains('easyplay'),
      );

      final black = LanClientConnection(const GoConfig(boardSize: 9));
      final white = LanClientConnection(const GoConfig(boardSize: 9));
      final wrongPin = LanClientConnection(const GoConfig(boardSize: 9));
      await expectLater(
        wrongPin.connect(Uri.parse('ws://127.0.0.1:$port'), token: 'wrong'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('口令错误'),
          ),
        ),
      );
      await wrongPin.close();
      await black.connect(
        Uri.parse('ws://127.0.0.1:$port'),
        token: 'test-token',
      );
      await white.connect(
        Uri.parse('ws://127.0.0.1:$port'),
        token: 'test-token',
      );
      expect(black.side, Side.black);
      expect(white.side, Side.white);
      host.startMatch();
      final third = LanClientConnection(const GoConfig(boardSize: 9));
      await expectLater(
        third.connect(Uri.parse('ws://127.0.0.1:$port'), token: 'test-token'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('房间已满'),
          ),
        ),
      );
      await third.close();
      final event = LanMessage(LanMessageType.move, 1, {
        'side': 'B',
        'cell': [0, 0],
      });
      final deliveredFuture = white.messages.firstWhere(
        (message) => message.type == LanMessageType.move,
      );
      black.send(event);
      final delivered = await deliveredFuture;
      expect(delivered.seq, 1);
      expect(white.replica!.session.moves, hasLength(1));
      await black.close();
      await white.close();
      await host.close();
    },
  );

  test(
    'a disconnected client reclaims its side and syncs missed moves',
    () async {
      final host = LanHostServer(
        authority: LanAuthority(const GoConfig(boardSize: 9)),
        token: 'test-token',
      );
      await host.start(host: '127.0.0.1', port: 0);
      final uri = Uri.parse('ws://127.0.0.1:${host.port}');
      final black = LanClientConnection(const GoConfig(boardSize: 9));
      final white = LanClientConnection(const GoConfig(boardSize: 9));
      try {
        await black.connect(uri, token: 'test-token');
        await white.connect(uri, token: 'test-token');
        host.startMatch();
        final gone = host.playerCounts.firstWhere((count) => count == 1);
        await white.disconnect();
        await gone;
        final first = black.messages.firstWhere(
          (event) => event.type == LanMessageType.move,
        );
        black.send(
          LanMessage(LanMessageType.move, 1, {
            'side': 'B',
            'cell': [0, 0],
          }),
        );
        await first;
        final synced = white.messages.firstWhere(
          (event) => event.type == LanMessageType.stateSync && event.seq == 1,
        );
        await white.reconnect();
        await synced;
        expect(white.side, Side.white);
        expect(white.replica!.sgf, host.authority.sgf);
        expect(white.replica!.session.moves, hasLength(1));
      } finally {
        await black.close();
        await white.close();
        await host.close();
      }
    },
  );

  test('room limits repeated PIN guesses from one address', () async {
    final host = LanHostServer(
      authority: LanAuthority(const GoConfig(boardSize: 9)),
      token: '1234',
    );
    await host.start(host: '127.0.0.1', port: 0);
    final uri = Uri.parse('ws://127.0.0.1:${host.port}');
    try {
      for (var i = 0; i < 5; i++) {
        final client = LanClientConnection(const GoConfig(boardSize: 9));
        await expectLater(
          client.connect(uri, token: 'wrong'),
          throwsStateError,
        );
        await client.close();
      }
      final client = LanClientConnection(const GoConfig(boardSize: 9));
      await expectLater(
        client.connect(uri, token: '1234'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('口令尝试过多'),
          ),
        ),
      );
      await client.close();
    } finally {
      await host.close();
    }
  });
}
