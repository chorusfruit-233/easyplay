import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/lan/chess_lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_transport.dart';

class Match {
  final host = ChessAuthority();
  final white = ChessLanReplica(), black = ChessLanReplica();
  LanMessage send(
    LanMessageType type,
    Side side, [
    Map<String, Object?> body = const {},
  ]) {
    final event = host.submit(
      side,
      LanMessage(type, host.seq + 1, {
        'side': LanMessage.sideCode(side),
        ...body,
      }),
    );
    expect(event.type, type);
    for (final replica in [white, black]) {
      expect(replica.receive(event), true);
      expect(replica.session.fen, host.session.fen);
      expect(replica.session.result, host.session.result);
      expect(replica.session.repetitionCount, host.session.repetitionCount);
    }
    return event;
  }

  void moves(String line) {
    for (final move in line.split(' ')) {
      send(LanMessageType.move, host.session.turn, {'move': move});
    }
  }

  void sync() {
    final replica = ChessLanReplica();
    expect(replica.receive(host.sync(replica.stateRequest())), true);
    expect(replica.session.fen, host.session.fen);
    expect(replica.session.result, host.session.result);
    expect(replica.session.repetitionCount, host.session.repetitionCount);
  }
}

void main() {
  test('reject invalid, duplicate and gap without committing or mutating', () {
    final m = Match();
    for (final event in [
      LanMessage(LanMessageType.move, 1, {'side': 'W', 'move': 'e2e5'}),
      LanMessage(LanMessageType.move, 2, {'side': 'W', 'move': 'e2e4'}),
      LanMessage(LanMessageType.move, 1, {'side': 'B', 'move': 'e7e5'}),
    ]) {
      expect(m.host.submit(Side.white, event).type, LanMessageType.rejected);
      expect(m.host.seq, 0);
    }
    m.moves('e2e4');
    expect(
      m.white.receive(
        LanMessage(LanMessageType.move, 1, {'side': 'W', 'move': 'e2e4'}),
      ),
      false,
    );
    expect(
      m.black.receive(
        LanMessage(LanMessageType.move, 3, {'side': 'B', 'move': 'e7e5'}),
      ),
      false,
    );
    m.sync();
  });
  test(
    'castle, en passant, promotions, checkmate replay with equal FEN at every ply',
    () {
      for (final line in [
        'e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 e1g1',
        'e2e4 a7a6 e4e5 d7d5 e5d6',
        'a2a4 h7h5 a4a5 h5h4 a5a6 h4h3 a6b7 h3g2 b7a8n',
        'f2f3 e7e5 g2g4 d8h4',
      ]) {
        final m = Match();
        m.moves(line);
        m.sync();
      }
    },
  );
  test(
    'negotiations block moves, reject self-accept and stale responses; undo replays',
    () {
      final m = Match();
      m.moves('e2e4 e7e5');
      final undo = m.send(LanMessageType.undoRequest, Side.black);
      expect(
        m.host
            .submit(
              Side.black,
              LanMessage(LanMessageType.undoAccept, m.host.seq + 1, {
                'side': 'B',
                'requestSeq': undo.seq,
              }),
            )
            .type,
        LanMessageType.rejected,
      );
      expect(
        m.host
            .submit(
              Side.white,
              LanMessage(LanMessageType.move, m.host.seq + 1, {
                'side': 'W',
                'move': 'g1f3',
              }),
            )
            .type,
        LanMessageType.rejected,
      );
      m.send(LanMessageType.undoAccept, Side.white, {'requestSeq': undo.seq});
      expect(m.host.session.moves.length, 1);
      m.sync();
      final draw = m.send(LanMessageType.drawRequest, Side.white);
      m.send(LanMessageType.drawReject, Side.black, {'requestSeq': draw.seq});
      final again = m.send(LanMessageType.drawRequest, Side.black);
      m.send(LanMessageType.drawAccept, Side.white, {'requestSeq': again.seq});
      expect(m.host.session.result?.reason, ChessEndReason.drawAgreement);
      m.sync();
    },
  );
  test('claims, automatic draw, resignation and negotiation timeout sync', () {
    final m = Match();
    m.moves('g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8');
    m.send(LanMessageType.drawClaim, Side.white);
    expect(m.host.session.result?.reason, ChessEndReason.threefoldRepetition);
    m.sync();
    final automatic = Match();
    for (var i = 0; i < 4; i++) {
      automatic.moves('g1f3 g8f6 f3g1 f6g8');
    }
    expect(
      automatic.host.session.result?.reason,
      ChessEndReason.fivefoldRepetition,
    );
    automatic.sync();
    final resigned = Match();
    resigned.send(LanMessageType.resign, Side.black);
    resigned.sync();
    final timeout = Match();
    final event = timeout.send(LanMessageType.drawRequest, Side.white);
    final expired = timeout.host.expireDraw(event.seq)!;
    expect(timeout.white.receive(expired), true);
    expect(timeout.black.receive(expired), true);
    timeout.sync();
  });
  test(
    'real shared WebSocket handshake, seat assignment, reconnect and full stateSync',
    () async {
      final host = LanHostServer(
        chessAuthority: ChessAuthority(),
        token: '1234',
      );
      await host.start(host: '127.0.0.1', port: 0);
      final white = LanClientConnection.chess(),
          black = LanClientConnection.chess();
      addTearDown(() async {
        await white.close();
        await black.close();
        await host.close();
      });
      final uri = Uri.parse('ws://127.0.0.1:${host.port}');
      await white.connect(uri, token: '1234');
      await black.connect(uri, token: '1234');
      expect(white.side, Side.white);
      expect(black.side, Side.black);
      expect(white.chessReplica, isNotNull);
      final started = white.messages.firstWhere(
        (m) => m.type == LanMessageType.matchStart,
      );
      host.startMatch();
      await started;
      final received = black.messages.firstWhere(
        (m) => m.type == LanMessageType.move,
      );
      white.send(
        LanMessage(LanMessageType.move, 1, {'side': 'W', 'move': 'e2e4'}),
      );
      await received;
      expect(black.chessReplica!.session.fen, host.chessAuthority!.session.fen);
      final left = host.playerCounts.firstWhere((count) => count == 1);
      await black.disconnect();
      await left;
      await black.reconnect();
      // connect must not resolve until the authoritative snapshot has applied.
      expect(black.side, Side.black);
      expect(black.seq, 1);
      expect(black.started, true);
      expect(black.chessReplica!.session.fen, white.chessReplica!.session.fen);
      final sync = white.messages.firstWhere(
        (m) => m.type == LanMessageType.move,
      );
      black.send(
        LanMessage(LanMessageType.move, 2, {'side': 'B', 'move': 'e7e5'}),
      );
      await sync;
      expect(white.chessReplica!.session.fen, host.chessAuthority!.session.fen);
    },
  );
  test('rulesVersion and malformed UCI are rejected in handshake/codec', () {
    expect(
      () => LanMessage(LanMessageType.hello, 0, {
        'roomVersion': lanProtocolVersion,
        'game': 'chess',
        'rulesVersion': 999,
        'token': '1234',
      }),
      throwsFormatException,
    );
    expect(
      () => LanMessage(LanMessageType.move, 1, {'side': 'W', 'move': 'e2e9'}),
      throwsFormatException,
    );
  });
}
