import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/draughts/draughts_variant.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'package:easyplay/lan/rtc_manual_signaling.dart';
import 'package:easyplay/lan/rtc_room.dart';

Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  for (final game in [
    'go',
    'chess',
    ...DraughtsVariant.values.map((v) => v.name),
  ]) {
    test(
      '$game: authority, replica, negotiation and authenticated reconnect',
      () async {
        final variant = DraughtsVariant.values
            .where((v) => v.name == game)
            .firstOrNull;
        final invite = RtcInvitation.offer(
          variant == null ? game : 'draughts',
          'v=0\r\n',
          variant: variant,
        );
        final room = RtcRoom.host(invite);
        final guest = RtcMatchClient(invite);
        Future<void> connectGuest() async {
          final (server, client) = MemoryTransport.pair();
          await room.attachPeer(server);
          await guest.bind(client);
        }

        try {
          await room.prepareHost();
          await connectGuest();
          final host = room.client;
          expect(host.side, room.coordinator!.firstSide);
          expect(guest.side, host.side!.opponent);
          expect(host.started, isFalse);
          final before = host.messages.firstWhere(
            (m) => m.type == LanMessageType.rejected,
          );
          host.send(
            LanMessage(LanMessageType.resign, 1, {
              'side': LanMessage.sideCode(host.side!),
            }),
          );
          expect((await before).body['reason'], contains('等待'));
          room.coordinator!.startMatch();
          await drain();
          expect(host.started && guest.started, isTrue);
          final Map<String, Object?> move;
          if (game == 'go') {
            move = {
              'cell': [3, 3],
            };
          } else if (game == 'chess') {
            move = {'move': 'e2e4'};
          } else {
            move = {
              'path': room.coordinator!.draughtsAuthority!.session
                  .legalMoves()
                  .first
                  .path
                  .map((c) => [c.row, c.col])
                  .toList(),
            };
          }
          host.send(
            LanMessage(LanMessageType.move, 1, {
              'side': LanMessage.sideCode(host.side!),
              ...move,
            }),
          );
          await drain();
          expect(host.seq, 1);
          expect(guest.seq, 1);
          final forged = guest.messages.firstWhere(
            (m) => m.type == LanMessageType.rejected,
          );
          guest.send(
            LanMessage(LanMessageType.resign, 2, {
              'side': LanMessage.sideCode(host.side!),
            }),
          );
          expect((await forged).body['reason'], contains('代替'));
          expect(room.coordinator!.seq, 1);
          host.send(
            LanMessage(LanMessageType.undoRequest, 2, {
              'side': LanMessage.sideCode(host.side!),
            }),
          );
          await drain();
          guest.send(
            LanMessage(LanMessageType.undoAccept, 3, {
              'side': LanMessage.sideCode(guest.side!),
              'requestSeq': 2,
            }),
          );
          await drain();
          expect(host.seq, 3);
          expect(guest.seq, 3);
          await guest.disconnect();
          await drain();
          expect(room.coordinator!.playerCount, 1);
          await connectGuest();
          expect(guest.side, host.side!.opponent);
          expect(guest.seq, 3);
          if (game == 'go') {
            host.send(
              LanMessage(LanMessageType.pass, 4, {
                'side': LanMessage.sideCode(host.side!),
              }),
            );
            await drain();
            guest.send(
              LanMessage(LanMessageType.pass, 5, {
                'side': LanMessage.sideCode(guest.side!),
              }),
            );
            await drain();
            host.send(
              LanMessage(LanMessageType.scoreProposal, 6, {
                'side': LanMessage.sideCode(host.side!),
                'deadStones': [],
              }),
            );
            await drain();
            guest.send(
              LanMessage(LanMessageType.scoreAccept, 7, {
                'side': LanMessage.sideCode(guest.side!),
                'requestSeq': 6,
              }),
            );
            await drain();
          } else {
            host.send(
              LanMessage(LanMessageType.drawRequest, 4, {
                'side': LanMessage.sideCode(host.side!),
              }),
            );
            await drain();
            guest.send(
              LanMessage(LanMessageType.drawAccept, 5, {
                'side': LanMessage.sideCode(guest.side!),
                'requestSeq': 4,
              }),
            );
            await drain();
          }
          expect(room.coordinator!.gameOver, isTrue);
          final requestSeq = host.seq + 1;
          host.send(
            LanMessage(LanMessageType.rematchRequest, requestSeq, {
              'side': LanMessage.sideCode(host.side!),
            }),
          );
          await drain();
          guest.send(
            LanMessage(LanMessageType.rematchAccept, requestSeq + 1, {
              'side': LanMessage.sideCode(guest.side!),
              'requestSeq': requestSeq,
            }),
          );
          await drain();
          expect(room.coordinator!.gameOver, isFalse);
          expect(host.seq, guest.seq);
        } finally {
          await guest.close();
          await room.close();
        }
      },
    );
  }
  test(
    'RTC guest cannot claim host seat, reuse host token or add a third player',
    () async {
      final invite = RtcInvitation.offer('chess', 'v=0\r\n');
      final room = RtcRoom.host(invite);
      await room.prepareHost();
      Future<void> rejected({Side? side, String? token}) async {
        final client = RtcMatchClient(invite)..side = side;
        final (server, peer) = MemoryTransport.pair();
        await room.attachPeer(server);
        await expectLater(client.bind(peer, token: token), throwsStateError);
        await client.close();
      }

      try {
        await rejected(side: room.coordinator!.firstSide);
        await rejected(token: 'wrong-token');
        final guest = RtcMatchClient(invite);
        final (server, peer) = MemoryTransport.pair();
        await room.attachPeer(server);
        await guest.bind(peer);
        await rejected();
        await guest.close();
      } finally {
        await room.close();
      }
    },
  );
}
