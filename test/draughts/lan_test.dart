import 'package:flutter_test/flutter_test.dart';

import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/lan/draughts_lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_transport.dart';

void main() {
  test('one committed move is replayed into the replica', () {
    final authority = DraughtsAuthority(DraughtsVariant.english);
    final replica = DraughtsLanReplica(DraughtsVariant.english);
    final move = authority.session.legalMoves().first;
    final event = LanMessage(LanMessageType.move, 1, {
      'side': LanMessage.sideCode(authority.session.turn),
      'path': move.path.map((cell) => [cell.row, cell.col]).toList(),
    });

    final accepted = authority.submit(authority.session.turn, event);
    expect(accepted.type, LanMessageType.move);
    expect(authority.seq, 1);
    expect(authority.session.moves, hasLength(1));
    expect(replica.receive(authority.sync(replica.stateRequest())), isTrue);
    expect(replica.seq, 1);
    expect(replica.session.moves, authority.session.moves);
    expect(
      replica.session.position.signature(replica.session.turn),
      authority.session.position.signature(authority.session.turn),
    );
  });

  test('three-jump capture is committed as one sequence number', () {
    final authority = DraughtsAuthority(DraughtsVariant.english);
    authority.session.restore(
      position: position(8, {
        const Cell(0, 1): const DraughtsPiece(Side.black),
        const Cell(1, 2): const DraughtsPiece(Side.white),
        const Cell(3, 4): const DraughtsPiece(Side.white),
        const Cell(5, 6): const DraughtsPiece(Side.white),
        const Cell(7, 0): const DraughtsPiece(Side.white),
      }),
      turn: Side.black,
      history: const [],
    );
    final move = authority.session.legalMoves().single;

    final event = authority.submit(
      Side.black,
      LanMessage(LanMessageType.move, 1, {
        'side': 'B',
        'path': move.path.map((cell) => [cell.row, cell.col]).toList(),
      }),
    );

    expect(event.type, LanMessageType.move);
    expect(authority.seq, 1);
    expect(authority.session.moves, hasLength(1));
    expect(authority.session.moves.single.captures, hasLength(3));
  });

  test('illegal and partial paths do not change authority state or seq', () {
    final authority = DraughtsAuthority(DraughtsVariant.english);
    final before = authority.session.position.signature(authority.session.turn);
    final rejected = authority.submit(
      Side.black,
      LanMessage(LanMessageType.move, 1, {
        'side': 'B',
        'path': [
          [2, 1],
          [4, 3],
        ],
      }),
    );

    expect(rejected.type, LanMessageType.rejected);
    expect(authority.seq, 0);
    expect(authority.session.moves, isEmpty);
    expect(
      authority.session.position.signature(authority.session.turn),
      before,
    );
  });

  test(
    'LAN handshake rejects a variant mismatch and accepts an exact match',
    () async {
      final server = LanHostServer(
        draughtsAuthority: DraughtsAuthority(DraughtsVariant.english),
        token: '1234',
      );
      await server.start(host: '127.0.0.1', port: 0);
      final matching = LanClientConnection.draughts(DraughtsVariant.english);
      final mismatched = LanClientConnection.draughts(
        DraughtsVariant.international,
      );
      try {
        await matching.connect(
          Uri.parse('ws://127.0.0.1:${server.port}'),
          token: '1234',
        );
        await expectLater(
          mismatched.connect(
            Uri.parse('ws://127.0.0.1:${server.port}'),
            token: '1234',
          ),
          throwsStateError,
        );
        expect(matching.draughtsReplica, isNotNull);
        expect(server.playerCount, 1);
      } finally {
        await mismatched.close();
        await matching.close();
        await server.close();
      }
    },
  );

  test('same variant reconnect replays the complete event log', () async {
    final authority = DraughtsAuthority(DraughtsVariant.english);
    final server = LanHostServer(draughtsAuthority: authority, token: 'pin');
    await server.start(host: '127.0.0.1', port: 0);
    final host = LanClientConnection.draughts(DraughtsVariant.english);
    final guest = LanClientConnection.draughts(DraughtsVariant.english);
    try {
      await host.connect(
        Uri.parse('ws://127.0.0.1:${server.port}'),
        token: 'pin',
      );
      await guest.connect(
        Uri.parse('ws://127.0.0.1:${server.port}'),
        token: 'pin',
      );
      server.startMatch();
      final moved = guest.messages.firstWhere(
        (message) => message.type == LanMessageType.move,
      );
      final move = authority.session.legalMoves().first;
      host.send(
        LanMessage(LanMessageType.move, 1, {
          'side': LanMessage.sideCode(host.side!),
          'path': move.path.map((cell) => [cell.row, cell.col]).toList(),
        }),
      );
      await moved;
      await guest.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await guest.reconnect();

      expect(guest.draughtsReplica!.seq, 1);
      expect(guest.draughtsReplica!.session.moves, hasLength(1));
      expect(
        guest.draughtsReplica!.session.position.signature(
          guest.draughtsReplica!.session.turn,
        ),
        authority.session.position.signature(authority.session.turn),
      );
    } finally {
      await guest.close();
      await host.close();
      await server.close();
    }
  });
}

DraughtsPosition position(int size, Map<Cell, DraughtsPiece> pieces) {
  var result = DraughtsPosition(size, List.filled(size * size, null));
  for (final entry in pieces.entries) {
    result = result.copyWithCell(entry.key, entry.value);
  }
  return result;
}
