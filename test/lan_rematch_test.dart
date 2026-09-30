import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/game_session.dart' show GoConfig;
import 'package:easyplay/lan/chess_lan_game.dart';
import 'package:easyplay/lan/draughts_lan_game.dart';
import 'package:easyplay/lan/lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final game in [
    'go',
    'chess',
    ...DraughtsVariant.values.map((v) => v.name),
  ]) {
    test(
      '$game: host starts, own undo, rematch consent and reconnect across rounds',
      () async {
        final room = _Room(game);
        addTearDown(room.close);
        await room.open();
        expect(room.host.side, room.firstSide);
        expect(room.guest.side, room.firstSide.opponent);
        expect(room.turn, room.host.side);
        final initial = room.signature;

        await room.reject(room.host, LanMessageType.rematchRequest);
        await room.commit(room.host, LanMessageType.move, room.nextMove);
        expect(room.canUndo(room.host.side!), isTrue);
        expect(room.canUndo(room.guest.side!), isFalse);
        await room.reject(room.guest, LanMessageType.undoRequest);
        await room.commit(room.guest, LanMessageType.move, room.nextMove);
        expect(room.canUndo(room.host.side!), isFalse);
        await room.reject(room.host, LanMessageType.undoRequest);
        await room.commit(room.guest, LanMessageType.undoRequest);
        final undo = room.server.seq;
        await room.reject(room.guest, LanMessageType.undoAccept, {
          'requestSeq': undo,
        });
        await room.reject(room.host, LanMessageType.move, room.nextMove);
        await room.commit(room.host, LanMessageType.undoAccept, {
          'requestSeq': undo,
        });
        expect(room.moveCount, 1);
        expect(room.turn, room.guest.side);

        await room.commit(room.guest, LanMessageType.resign);
        final finished = room.signature;
        await room.commit(room.host, LanMessageType.rematchRequest);
        final declined = room.server.seq;
        await room.reject(room.host, LanMessageType.rematchAccept, {
          'requestSeq': declined,
        });
        await room.reject(room.guest, LanMessageType.rematchAccept, {
          'requestSeq': declined - 1,
        });
        await room.commit(room.guest, LanMessageType.rematchReject, {
          'requestSeq': declined,
        });
        expect(room.signature, finished);
        expect(room.round, 1);

        await room.commit(room.guest, LanMessageType.rematchRequest);
        final rematch = room.server.seq;
        final disconnected = room.server.playerCounts.firstWhere(
          (count) => count == 1,
        );
        await room.guest.disconnect();
        await disconnected;
        // The guest has consented, then misses both the reset and the next move.
        await room.commitAlone(room.host, LanMessageType.rematchAccept, {
          'requestSeq': rematch,
        });
        expect(room.round, 2);
        expect(room.moveCount, 0);
        expect(room.signature, initial);
        expect(room.turn, room.host.side);
        expect(room.canUndo(room.host.side!), isFalse);
        await room.reject(room.host, LanMessageType.rematchAccept, {
          'requestSeq': rematch,
        });
        await room.commitAlone(room.host, LanMessageType.move, room.nextMove);
        await room.guest.reconnect();
        expect(room.guest.side, room.firstSide.opponent);
        expect(room.guest.started, isTrue);
        expect(room.guest.seq, room.server.seq);
        expect(room.replicaRound(room.guest), 2);
        expect(room.replicaSignature(room.guest), room.signature);
        await room.commit(room.guest, LanMessageType.move, room.nextMove);
        expect(room.moveCount, 2);
      },
    );
  }

  test(
    'Go requires confirmed scoring before rematch and preserves handicap/config',
    () {
      const config = GoConfig(boardSize: 9, komi: .5, handicap: 2);
      final host = LanAuthority(config);
      LanMessage send(
        LanMessageType type,
        Side side, [
        Map<String, Object?> body = const {},
      ]) => host.submit(
        side,
        LanMessage(type, host.seq + 1, {
          'side': LanMessage.sideCode(side),
          ...body,
        }),
      );
      send(LanMessageType.pass, Side.white);
      send(LanMessageType.pass, Side.black);
      expect(
        send(LanMessageType.rematchRequest, Side.white).type,
        LanMessageType.rejected,
      );
      final proposal = send(LanMessageType.scoreProposal, Side.white, {
        'deadStones': [],
      });
      send(LanMessageType.scoreAccept, Side.black, {
        'requestSeq': proposal.seq,
      });
      final request = send(LanMessageType.rematchRequest, Side.black);
      send(LanMessageType.rematchAccept, Side.white, {
        'requestSeq': request.seq,
      });
      expect(host.session.goConfig.handicap, 2);
      expect(host.session.goConfig.komi, .5);
      expect(host.session.turn, Side.white);
      expect(host.session.goScoreConfirmed, isFalse);
      expect(host.session.moves, isEmpty);
      final restored = LanReplica(config);
      expect(restored.receive(host.sync(restored.stateRequest())), isTrue);
      expect(restored.round, 2);
      expect(restored.sgf, host.sgf);
    },
  );
}

class _Room {
  _Room(this.game) {
    if (game == 'chess') {
      server = LanHostServer(chessAuthority: ChessAuthority(), token: 'pin');
      host = LanClientConnection.chess();
      guest = LanClientConnection.chess();
      firstSide = Side.white;
    } else if (game == 'go') {
      const config = GoConfig(boardSize: 9);
      server = LanHostServer(authority: LanAuthority(config), token: 'pin');
      host = LanClientConnection(config);
      guest = LanClientConnection(config);
      firstSide = Side.black;
    } else {
      final variant = DraughtsVariant.values.byName(game);
      server = LanHostServer(
        draughtsAuthority: DraughtsAuthority(variant),
        token: 'pin',
      );
      host = LanClientConnection.draughts(variant);
      guest = LanClientConnection.draughts(variant);
      firstSide = DraughtsRules.forVariant(variant).firstMove;
    }
  }
  final String game;
  late final LanHostServer server;
  late final LanClientConnection host, guest;
  late final Side firstSide;
  Side get turn =>
      server.chessAuthority?.session.turn ??
      server.draughtsAuthority?.session.turn ??
      server.authority.session.turn;
  int get moveCount =>
      server.chessAuthority?.session.moves.length ??
      server.draughtsAuthority?.session.moves.length ??
      server.authority.session.moves.length;
  int get round =>
      server.chessAuthority?.round ??
      server.draughtsAuthority?.round ??
      server.authority.round;
  int replicaRound(LanClientConnection client) =>
      client.chessReplica?.round ??
      client.draughtsReplica?.round ??
      client.replica!.round;
  bool canUndo(Side side) =>
      server.chessAuthority?.canRequestUndo(side) ??
      server.draughtsAuthority?.canRequestUndo(side) ??
      server.authority.canRequestUndo(side);
  String get signature =>
      server.chessAuthority?.session.fen ??
      server.draughtsAuthority?.session.position.signature(turn) ??
      server.authority.sgf;
  String replicaSignature(LanClientConnection client) =>
      client.chessReplica?.session.fen ??
      client.draughtsReplica?.session.position.signature(
        client.draughtsReplica!.session.turn,
      ) ??
      client.replica!.sgf;
  Map<String, Object?> get nextMove {
    if (game == 'chess') return {'move': turn == Side.white ? 'e2e4' : 'e7e5'};
    if (game == 'go') {
      return {
        'cell': turn == Side.black ? [0, 0] : [1, 1],
      };
    }
    return {
      'path': server.draughtsAuthority!.session
          .legalMoves()
          .first
          .path
          .map((cell) => [cell.row, cell.col])
          .toList(),
    };
  }

  Future<void> open() async {
    await server.start(host: '127.0.0.1', port: 0);
    final uri = Uri.parse('ws://127.0.0.1:${server.port}');
    await host.connect(uri, token: 'pin');
    await guest.connect(uri, token: 'pin');
    final started = Future.wait(
      [host, guest].map(
        (client) => client.messages.firstWhere(
          (m) => m.type == LanMessageType.matchStart,
        ),
      ),
    );
    server.startMatch();
    await started;
  }

  Future<void> commit(
    LanClientConnection client,
    LanMessageType type, [
    Map<String, Object?> body = const {},
  ]) => _commit(client, type, body);

  Future<void> commitAlone(
    LanClientConnection client,
    LanMessageType type,
    Map<String, Object?> body,
  ) => _commit(client, type, body, guestConnected: false);

  Future<void> _commit(
    LanClientConnection client,
    LanMessageType type,
    Map<String, Object?> body, {
    bool guestConnected = true,
  }) async {
    final peers = [host, if (guestConnected) guest];
    final received = Future.wait(
      peers.map((peer) => peer.messages.firstWhere((m) => m.type == type)),
    );
    client.send(
      LanMessage(type, server.seq + 1, {
        'side': LanMessage.sideCode(client.side!),
        ...body,
      }),
    );
    await received.timeout(const Duration(seconds: 5));
    for (final peer in peers) {
      expect(peer.seq, server.seq);
      expect(replicaRound(peer), round);
      expect(replicaSignature(peer), signature);
    }
  }

  Future<void> reject(
    LanClientConnection client,
    LanMessageType type, [
    Map<String, Object?> body = const {},
  ]) async {
    final before = server.seq;
    final received = client.messages.firstWhere(
      (m) => m.type == LanMessageType.rejected,
    );
    client.send(
      LanMessage(type, before + 1, {
        'side': LanMessage.sideCode(client.side!),
        ...body,
      }),
    );
    await received.timeout(const Duration(seconds: 5));
    expect(server.seq, before);
  }

  Future<void> close() async {
    await host.close();
    await guest.close();
    await server.close();
  }
}
