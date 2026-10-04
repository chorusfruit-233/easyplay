import 'package:flutter_test/flutter_test.dart';

import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/lan/gomoku_lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';

LanMessage move(int seq, String side, Cell cell) =>
    LanMessage(LanMessageType.move, seq, {
      'side': side,
      'cell': [cell.row, cell.col],
    });

void main() {
  for (final variant in GomokuVariant.values) {
    test('${variant.name} survives undo, rematch and reconnect', () {
      final host = GomokuLanAuthority(variant: variant);
      final client = GomokuLanReplica(variant: variant);
      void commit(Side side, LanMessageType type, Map<String, Object?> body) {
        final event = host.submit(
          side,
          LanMessage(type, host.seq + 1, {
            'side': LanMessage.sideCode(side),
            ...body,
          }),
        );
        expect(event.type, type);
        expect(client.receive(event), isTrue);
      }

      commit(Side.black, LanMessageType.move, {
        'cell': [7, 7],
      });
      commit(Side.black, LanMessageType.undoRequest, {});
      commit(Side.white, LanMessageType.undoAccept, {'requestSeq': host.seq});
      expect(client.session.moves, isEmpty);
      expect(client.session.variant, variant);
      commit(Side.black, LanMessageType.resign, {});
      commit(Side.white, LanMessageType.rematchRequest, {});
      commit(Side.black, LanMessageType.rematchAccept, {
        'requestSeq': host.seq,
      });
      expect(host.round, 2);
      expect(host.session.variant, variant);
      expect(client.session.variant, variant);
      final reconnected = GomokuLanReplica(variant: variant);
      expect(
        reconnected.receive(host.sync(reconnected.stateRequest())),
        isTrue,
      );
      expect(reconnected.session.variant, variant);
      expect(reconnected.session.toJson(), host.session.toJson());
      expect(reconnected.round, 2);
    });
  }

  test(
    'sync rejects missing, unknown, old and mismatched rules atomically',
    () {
      final host = GomokuLanAuthority(variant: GomokuVariant.renju);
      final client = GomokuLanReplica(variant: GomokuVariant.renju);
      final event = host.submit(Side.black, move(1, 'B', const Cell(7, 7)));
      expect(client.receive(event), isTrue);
      final before = client.session.toJson();
      final valid = host.sync(client.stateRequest());
      for (final body in [
        {...valid.body}..remove('variant'),
        {...valid.body, 'variant': 'swap2'},
        {...valid.body, 'rulesVersion': 1},
      ]) {
        expect(
          () => LanMessage(LanMessageType.stateSync, valid.seq, body),
          throwsFormatException,
        );
        expect(client.session.toJson(), before);
        expect(client.seq, 1);
      }
      expect(
        client.receive(
          LanMessage(LanMessageType.stateSync, valid.seq, {
            ...valid.body,
            'variant': GomokuVariant.standard.name,
          }),
        ),
        isFalse,
      );
      expect(client.session.toJson(), before);
      expect(client.seq, 1);
      expect(client.receive(valid), isTrue);
    },
  );

  test('Renju forbidden move is rejected by both host and replica', () {
    final host = GomokuLanAuthority(variant: GomokuVariant.renju);
    final client = GomokuLanReplica(variant: GomokuVariant.renju);
    const black = [Cell(7, 6), Cell(7, 8), Cell(6, 7), Cell(8, 7)];
    const white = [Cell(0, 0), Cell(0, 2), Cell(2, 0), Cell(2, 2)];
    for (var i = 0; i < black.length; i++) {
      for (final (side, cell) in [
        (Side.black, black[i]),
        (Side.white, white[i]),
      ]) {
        final event = host.submit(
          side,
          move(host.seq + 1, LanMessage.sideCode(side), cell),
        );
        expect(event.type, LanMessageType.move);
        expect(client.receive(event), isTrue);
      }
    }
    final before = host.session.toJson();
    final forbidden = move(host.seq + 1, 'B', const Cell(7, 7));
    final rejection = host.submit(Side.black, forbidden);
    expect(rejection.type, LanMessageType.rejected);
    expect(rejection.body['reason'], contains('三'));
    expect(client.receive(forbidden), isFalse);
    expect(host.seq, 8);
    expect(client.seq, 8);
    expect(host.session.toJson(), before);
    expect(client.session.toJson(), before);
  });

  test('standard overline remains playable without a network win', () {
    final host = GomokuLanAuthority(variant: GomokuVariant.standard);
    final client = GomokuLanReplica(variant: GomokuVariant.standard);
    const columns = [2, 3, 4, 6, 7, 5];
    for (var i = 0; i < columns.length; i++) {
      final black = host.submit(
        Side.black,
        move(host.seq + 1, 'B', Cell(7, columns[i])),
      );
      expect(black.type, LanMessageType.move);
      expect(client.receive(black), isTrue);
      if (i < columns.length - 1) {
        final white = host.submit(
          Side.white,
          move(host.seq + 1, 'W', Cell(i * 2, 0)),
        );
        expect(client.receive(white), isTrue);
      }
    }
    expect(host.session.gameOver, isFalse);
    expect(client.session.gameOver, isFalse);
    expect(client.session.winningLine, isEmpty);
    expect(client.session.toJson(), host.session.toJson());
  });

  test(
    'host commits moves once and rejects impersonation and illegal points',
    () {
      final host = GomokuLanAuthority();
      final client = GomokuLanReplica();
      final black = move(1, 'B', const Cell(7, 7));
      expect(host.submit(Side.white, black).type, LanMessageType.rejected);
      expect(host.seq, 0);
      expect(host.submit(Side.black, black).type, LanMessageType.move);
      expect(client.receive(black), isTrue);
      expect(client.receive(black), isFalse);
      expect(host.submit(Side.black, black).type, LanMessageType.rejected);
      expect(
        host.submit(Side.white, move(2, 'W', const Cell(7, 7))).type,
        LanMessageType.rejected,
      );
      expect(
        host.submit(Side.white, move(2, 'W', const Cell(15, 14))).type,
        LanMessageType.rejected,
      );
      expect(host.seq, 1);
      expect(host.session.toJson(), client.session.toJson());
    },
  );

  test('only opponent can approve unanswered undo, then sync replays it', () {
    final host = GomokuLanAuthority();
    host.submit(Side.black, move(1, 'B', const Cell(7, 7)));
    expect(host.canRequestUndo(Side.black), isTrue);
    expect(host.canRequestUndo(Side.white), isFalse);
    final request = LanMessage(LanMessageType.undoRequest, 2, {'side': 'B'});
    expect(host.submit(Side.black, request).type, request.type);
    expect(
      host.submit(Side.white, move(3, 'W', const Cell(6, 7))).type,
      LanMessageType.rejected,
    );
    expect(
      host
          .submit(
            Side.black,
            LanMessage(LanMessageType.undoAccept, 3, {
              'side': 'B',
              'requestSeq': 2,
            }),
          )
          .type,
      LanMessageType.rejected,
    );
    host.submit(
      Side.white,
      LanMessage(LanMessageType.undoAccept, 3, {'side': 'W', 'requestSeq': 2}),
    );
    expect(host.session.moves, isEmpty);
    expect(host.session.turn, Side.black);
    final client = GomokuLanReplica();
    expect(client.receive(host.sync(client.stateRequest())), isTrue);
    expect(client.seq, 3);
    expect(client.session.toJson(), host.session.toJson());
  });

  test('stale timeout cannot cancel a later undo request', () {
    final host = GomokuLanAuthority();
    host.submit(Side.black, move(1, 'B', const Cell(7, 7)));
    host.submit(
      Side.black,
      LanMessage(LanMessageType.undoRequest, 2, {'side': 'B'}),
    );
    expect(host.expireUndo(1), isNull);
    expect(host.expireUndo(2)?.type, LanMessageType.undoReject);
    expect(host.undoRequest, isNull);
    expect(host.session.moves, hasLength(1));
  });

  test(
    'winning move ends both copies and accepted rematch preserves sequence',
    () {
      final host = GomokuLanAuthority();
      final client = GomokuLanReplica();
      for (var col = 0; col < 5; col++) {
        final event = host.submit(
          Side.black,
          move(host.seq + 1, 'B', Cell(7, col)),
        );
        expect(client.receive(event), isTrue);
        if (col < 4) {
          expect(
            client.receive(
              host.submit(
                Side.white,
                move(host.seq + 1, 'W', Cell(col * 2, 14)),
              ),
            ),
            isTrue,
          );
        }
      }
      expect(client.session.winner, Side.black);
      expect(client.session.winningLine, hasLength(5));
      expect(
        host.submit(Side.white, move(host.seq + 1, 'W', const Cell(8, 8))).type,
        LanMessageType.rejected,
      );
      final requested = host.seq + 1;
      client.receive(
        host.submit(
          Side.white,
          LanMessage(LanMessageType.rematchRequest, requested, {'side': 'W'}),
        ),
      );
      client.receive(
        host.submit(
          Side.black,
          LanMessage(LanMessageType.rematchAccept, host.seq + 1, {
            'side': 'B',
            'requestSeq': requested,
          }),
        ),
      );
      expect(host.round, 2);
      expect(client.round, 2);
      expect(client.session.moves, isEmpty);
      expect(client.session.turn, Side.black);
      final reconnected = GomokuLanReplica();
      expect(
        reconnected.receive(host.sync(reconnected.stateRequest())),
        isTrue,
      );
      expect(reconnected.seq, host.seq);
      expect(reconnected.round, 2);
      expect(reconnected.session.toJson(), client.session.toJson());
    },
  );

  test('sync with a legal wire but illegal replay is rejected atomically', () {
    final client = GomokuLanReplica();
    expect(client.receive(move(1, 'B', const Cell(7, 7))), isTrue);
    final before = client.session.toJson();
    final invalid = LanMessage(LanMessageType.stateSync, 2, {
      'roomVersion': lanProtocolVersion,
      'game': 'gomoku',
      'boardSize': 15,
      'rulesVersion': gomokuRulesVersion,
      'variant': GomokuVariant.freestyle.name,
      'events': [
        move(1, 'B', const Cell(7, 7)).toWire(),
        move(2, 'W', const Cell(7, 7)).toWire(),
      ],
    });
    expect(client.receive(invalid), isFalse);
    expect(client.seq, 1);
    expect(client.session.toJson(), before);
  });

  test('Go pass and draughts path cannot mutate a Gomoku match', () {
    final host = GomokuLanAuthority();
    expect(
      host
          .submit(Side.black, LanMessage(LanMessageType.pass, 1, {'side': 'B'}))
          .type,
      LanMessageType.rejected,
    );
    expect(
      host
          .submit(
            Side.black,
            LanMessage(LanMessageType.move, 1, {
              'side': 'B',
              'path': [
                [7, 7],
                [7, 8],
              ],
            }),
          )
          .type,
      LanMessageType.rejected,
    );
    expect(host.seq, 0);
    expect(host.session.moves, isEmpty);
  });
}
