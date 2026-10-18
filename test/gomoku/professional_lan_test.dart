import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/lan/gomoku_lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final exchanged in [false, true]) {
    test(
      'network exchange=$exchanged: opening, proposals, undo, sync and resignation preserve identities',
      () {
        final host = GomokuLanAuthority();
        final replica = GomokuLanReplica();
        LanMessage request(
          Side player,
          LanMessageType type, [
          Map<String, Object?> body = const {},
        ]) => LanMessage(type, host.seq + 1, {
          'side': LanMessage.sideCode(player),
          ...body,
        });
        void commit(
          Side player,
          LanMessageType type, [
          Map<String, Object?> body = const {},
        ]) {
          final event = host.submit(player, request(player, type, body));
          expect(event.type, type);
          expect(replica.receive(event), isTrue);
          expect(replica.session.toJson(), host.session.toJson());
          final resumed = GomokuLanReplica();
          expect(resumed.receive(host.sync(resumed.stateRequest())), isTrue);
          expect(resumed.session.toJson(), host.session.toJson());
        }

        void place(Side player, Cell cell) =>
            commit(player, LanMessageType.move, {
              'cell': [cell.row, cell.col],
            });
        void reject(
          Side player,
          LanMessageType type, [
          Map<String, Object?> body = const {},
        ]) {
          final before = host.session.toJson(), seq = host.seq;
          final event = request(player, type, body);
          expect(host.submit(player, event).type, LanMessageType.rejected);
          expect(replica.receive(event), isFalse);
          expect(host.seq, seq);
          expect(host.session.toJson(), before);
          expect(replica.session.toJson(), before);
        }

        reject(Side.black, LanMessageType.move, {
          'cell': [0, 0],
        });
        place(Side.black, const Cell(7, 7));
        reject(Side.white, LanMessageType.move, {
          'cell': [6, 7],
        });
        place(Side.black, const Cell(6, 7));
        place(Side.black, const Cell(6, 6));
        reject(Side.black, LanMessageType.gomokuExchange, {'exchange': true});
        reject(Side.white, LanMessageType.move, {
          'cell': [8, 8],
        });
        commit(Side.white, LanMessageType.gomokuExchange, {
          'exchange': exchanged,
        });
        final blackPlayer = exchanged ? Side.white : Side.black;
        final whitePlayer = exchanged ? Side.black : Side.white;
        reject(Side.white, LanMessageType.gomokuExchange, {'exchange': true});
        place(whitePlayer, const Cell(8, 8));
        reject(blackPlayer, LanMessageType.gomokuDeclare, {'count': 2});
        commit(whitePlayer, LanMessageType.gomokuDeclare, {'count': 2});
        reject(whitePlayer, LanMessageType.gomokuExchange, {'exchange': true});
        commit(blackPlayer, LanMessageType.gomokuExchange, {'exchange': false});
        reject(whitePlayer, LanMessageType.move, {
          'cell': [8, 7],
        });
        place(blackPlayer, const Cell(8, 7));
        place(blackPlayer, const Cell(7, 8));
        expect(host.session.moves, hasLength(4));
        expect(host.session.proposals, hasLength(2));
        reject(blackPlayer, LanMessageType.move, {
          'cell': [7, 8],
        });
        reject(whitePlayer, LanMessageType.move, {
          'cell': [9, 9],
        });
        place(whitePlayer, const Cell(7, 8));
        expect(host.session.moves, hasLength(5));
        expect(host.session.actor, whitePlayer);
        commit(whitePlayer, LanMessageType.undoRequest);
        commit(blackPlayer, LanMessageType.undoAccept, {
          'requestSeq': host.seq,
        });
        expect(host.session.phase, GomokuPhase.selection);
        expect(host.session.proposals, hasLength(2));
        place(whitePlayer, const Cell(8, 7));
        place(whitePlayer, const Cell(7, 8));
        commit(blackPlayer, LanMessageType.resign);
        expect(host.session.winner, Side.white);
        commit(whitePlayer, LanMessageType.rematchRequest);
        commit(blackPlayer, LanMessageType.rematchAccept, {
          'requestSeq': host.seq,
        });
        expect(host.session.moves, isEmpty);
        expect(host.session.exchanged, isFalse);
        expect(host.session.actor, Side.black);
      },
    );
  }

  test(
    'exchange payload is typed and old entertainment handshakes are rejected',
    () {
      expect(
        () => LanMessage(LanMessageType.gomokuExchange, 1, {
          'side': 'W',
          'exchange': 1,
        }),
        throwsFormatException,
      );
      for (final variant in GomokuVariant.values.where(
        (v) => !v.playableRule,
      )) {
        expect(
          () => LanMessage(LanMessageType.hello, 0, {
            'game': 'gomoku',
            'roomVersion': lanProtocolVersion,
            'token': 'test',
            'boardSize': 15,
            'rulesVersion': gomokuRulesVersion,
            'variant': variant.name,
          }),
          throwsFormatException,
        );
      }
    },
  );
}
