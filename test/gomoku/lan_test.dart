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
  for (final variant in GomokuVariant.playable) {
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
      final host = GomokuLanAuthority(variant: GomokuVariant.soosyrv8);
      final client = GomokuLanReplica(variant: GomokuVariant.soosyrv8);
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
        () => LanMessage(LanMessageType.stateSync, valid.seq, {
          ...valid.body,
          'variant': GomokuVariant.standard.name,
        }),
        throwsFormatException,
      );
      expect(client.session.toJson(), before);
      expect(client.seq, 1);
      expect(client.receive(valid), isTrue);
    },
  );

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
      for (final (side, cell) in [
        (Side.black, const Cell(7, 7)),
        (Side.black, const Cell(6, 7)),
        (Side.black, const Cell(6, 6)),
      ]) {
        expect(
          client.receive(
            host.submit(
              side,
              move(host.seq + 1, LanMessage.sideCode(side), cell),
            ),
          ),
          isTrue,
        );
      }
      expect(
        client.receive(
          host.submit(
            Side.white,
            LanMessage(LanMessageType.gomokuExchange, host.seq + 1, {
              'side': 'W',
              'exchange': false,
            }),
          ),
        ),
        isTrue,
      );
      for (final (side, type, body) in [
        (
          Side.white,
          LanMessageType.move,
          <String, Object?>{
            'cell': [8, 8],
          },
        ),
        (
          Side.white,
          LanMessageType.gomokuDeclare,
          <String, Object?>{'count': 2},
        ),
        (
          Side.black,
          LanMessageType.gomokuExchange,
          <String, Object?>{'exchange': false},
        ),
      ]) {
        expect(
          client.receive(
            host.submit(
              side,
              LanMessage(type, host.seq + 1, {
                'side': LanMessage.sideCode(side),
                ...body,
              }),
            ),
          ),
          isTrue,
        );
      }
      for (final (side, cell) in [
        (Side.black, const Cell(8, 7)),
        (Side.black, const Cell(7, 8)),
        (Side.white, const Cell(7, 8)),
        (Side.white, const Cell(14, 14)),
      ]) {
        expect(
          client.receive(
            host.submit(
              side,
              move(host.seq + 1, LanMessage.sideCode(side), cell),
            ),
          ),
          isTrue,
        );
      }
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
      'variant': GomokuVariant.soosyrv8.name,
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
