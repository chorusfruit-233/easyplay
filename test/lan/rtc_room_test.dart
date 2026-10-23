import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/draughts/draughts_variant.dart';
import 'package:easyplay/gomoku/gomoku_variant.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'package:easyplay/lan/rtc_manual_signaling.dart';
import 'package:easyplay/lan/rtc_room.dart';
import '../support/drop_first_hello.dart';

class _DelayedHandshakeTransport implements MessageTransport {
  _DelayedHandshakeTransport(this.inner);
  final MessageTransport inner;
  final timers = <Timer>[];
  @override
  Stream<LanMessage> get messages => inner.messages;
  @override
  Stream<void> get disconnections => inner.disconnections;
  @override
  void send(LanMessage message) {
    timers.add(
      Timer(const Duration(milliseconds: 1200), () => inner.send(message)),
    );
  }

  @override
  Future<void> close() async {
    for (final timer in timers) {
      timer.cancel();
    }
    await inner.close();
  }
}

Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test('RTC local host survives suspension before a guest joins', () {
    fakeAsync((time) {
      final room = RtcRoom.host(RtcInvitation.offer('gomoku', 'v=0'));
      room.prepareHost();
      time.flushMicrotasks();
      expect(room.coordinator!.playerCount, 1);
      expect(time.periodicTimerCount, 0);
      time.elapseBlocking(const Duration(minutes: 5));
      time.elapse(const Duration(seconds: 5));
      expect(room.coordinator!.playerCount, 1);
      final guest = RtcMatchClient(room.invitation);
      final (server, endpoint) = MemoryTransport.pair();
      room.attachPeer(server);
      guest.bind(endpoint);
      time.flushMicrotasks();
      expect(room.coordinator!.playerCount, 2);
      room.coordinator!.startMatch();
      time.flushMicrotasks();
      expect(room.client.started && guest.started, isTrue);
      guest.close();
      room.close();
      time.flushMicrotasks();
      expect(time.pendingTimers, isEmpty);
    });
  });

  test(
    'legacy transport sends one HELLO even when its response takes over a second',
    () async {
      final invite = RtcInvitation.offer('gomoku', 'v=0');
      final room = RtcRoom.host(invite), guest = RtcMatchClient(invite);
      addTearDown(() async {
        await guest.close();
        await room.close();
      });
      await room.prepareHost();
      final (server, client) = MemoryTransport.pair();
      var hellos = 0;
      final subscription = server.messages.listen((message) {
        if (message.type == LanMessageType.hello) hellos++;
      });
      addTearDown(subscription.cancel);
      await room.attachPeer(_DelayedHandshakeTransport(server));
      await guest.bind(client);
      expect(hellos, 1);
      expect(guest.side, Side.white);
      expect(room.coordinator!.playerCount, 2);
    },
  );

  test(
    'RTC HELLO retry and duplicate response do not allocate another seat',
    () async {
      final invite = RtcInvitation.offer('gomoku', 'v=0');
      final room = RtcRoom.host(invite), guest = RtcMatchClient(invite);
      addTearDown(() async {
        await guest.close();
        await room.close();
      });
      await room.prepareHost();
      final (server, endpoint) = MemoryTransport.pair();
      await room.attachPeer(server);
      final transport = DropFirstHelloTransport(endpoint);
      final messages = <LanMessage>[];
      final subscription = guest.messages.listen(messages.add);
      addTearDown(subscription.cancel);
      await guest.bind(transport);
      await drain();
      expect(transport.attempts, 2);
      expect(guest.side, Side.white);
      expect(room.coordinator!.playerCount, 2);
      final seq = room.coordinator!.seq;
      final response = guest.messages.firstWhere(
        (m) => m.type == LanMessageType.stateSync,
      );
      transport.inner.send(transport.hello!);
      await response.timeout(const Duration(seconds: 2));
      await drain();
      expect(
        messages.where((m) => m.type == LanMessageType.helloAck),
        hasLength(2),
      );
      expect(room.coordinator!.seq, seq);
      expect(room.coordinator!.playerCount, 2);
      final rejected = guest.messages.firstWhere(
        (m) => m.type == LanMessageType.rejected,
      );
      transport.inner.send(
        LanMessage(LanMessageType.hello, 0, {
          ...transport.hello!.body,
          'token': 'other-identity',
        }),
      );
      expect((await rejected).body['reason'], contains('身份'));
      expect(room.coordinator!.playerCount, 2);
      expect(guest.side, Side.white);
    },
  );

  for (final game in [
    'go',
    'chess',
    'gomoku',
    ...DraughtsVariant.values.map((v) => v.name),
  ]) {
    test(
      '$game: authority, replica, negotiation and authenticated reconnect',
      () async {
        final variant = DraughtsVariant.values
            .where((v) => v.name == game)
            .firstOrNull;
        final invite = RtcInvitation.offer(
          variant == null
              ? (game.startsWith('gomoku') ? 'gomoku' : game)
              : 'draughts',
          'v=0\r\n',
          variant: variant,
          gomokuVariant: GomokuVariant.soosyrv8,
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
          if (game.startsWith('gomoku')) {
            expect(host.gomokuVariant, invite.gomokuVariant);
            expect(guest.gomokuReplica!.session.variant, invite.gomokuVariant);
          }
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
          if (game == 'go' || game.startsWith('gomoku')) {
            move = {
              'cell': game == 'gomoku' ? [7, 7] : [3, 3],
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
          } else if (game.startsWith('gomoku')) {
            host.send(
              LanMessage(LanMessageType.resign, 4, {
                'side': LanMessage.sideCode(host.side!),
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
          if (game.startsWith('gomoku')) {
            expect(host.gomokuReplica!.session.variant, invite.gomokuVariant);
            expect(guest.gomokuReplica!.session.variant, invite.gomokuVariant);
          }
          expect(host.seq, guest.seq);
        } finally {
          await guest.close();
          await room.close();
        }
      },
    );
  }
  test(
    'host reconnect clears an old online seat before creating a peer',
    () async {
      final room = RtcRoom.host(RtcInvitation.offer('chess', 'v=0\r\n'));
      final guest = RtcMatchClient(room.invitation);
      await room.prepareHost();
      addTearDown(() async {
        await guest.close();
        await room.close();
      });
      final (oldServer, oldClient) = MemoryTransport.pair();
      await room.attachPeer(oldServer);
      await guest.bind(oldClient);
      expect(room.coordinator!.playerCount, 2);
      // The host does not wait for a WebRTC remote-close event or a delay.
      await room.disconnectPeer();
      expect(room.coordinator!.playerCount, 1);
      final (server, client) = MemoryTransport.pair();
      await room.attachPeer(server);
      await guest.bind(client);
      expect(room.coordinator!.playerCount, 2);
      expect(guest.side, room.coordinator!.firstSide.opponent);
    },
  );
  test(
    'Gomoku RTC handshake rejects a different rule without consuming a seat',
    () async {
      final invite = RtcInvitation.offer(
        'gomoku',
        'v=0\r\n',
        gomokuVariant: GomokuVariant.soosyrv8,
      );
      final room = RtcRoom.host(invite);
      final guest = RtcMatchClient(
        RtcInvitation(
          sessionId: invite.sessionId,
          token: invite.token,
          game: 'gomoku',
          gomokuVariant: GomokuVariant.standard,
          type: 'offer',
          sdp: invite.sdp,
        ),
      );
      try {
        await room.prepareHost();
        final (server, peer) = MemoryTransport.pair();
        await room.attachPeer(server);
        await expectLater(guest.bind(peer), throwsFormatException);
        expect(room.coordinator!.playerCount, 1);
        expect(
          room.client.gomokuReplica!.session.variant,
          GomokuVariant.soosyrv8,
        );
        expect(
          room.coordinator!.gomokuAuthority!.session.variant,
          GomokuVariant.soosyrv8,
        );
      } finally {
        await guest.close();
        await room.close();
      }
    },
  );
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
