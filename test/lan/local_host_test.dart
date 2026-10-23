import 'dart:io';

import 'package:easyplay/draughts/draughts_variant.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/lan/chess_lan_game.dart';
import 'package:easyplay/lan/draughts_lan_game.dart';
import 'package:easyplay/lan/gomoku_lan_game.dart';
import 'package:easyplay/lan/lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_transport_io.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'package:easyplay/lan/rtc_manual_signaling.dart';
import 'package:easyplay/lan/rtc_room.dart';
import 'package:easyplay/lan/xiangqi_lan_game.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'suspending the scheduler expires a remote guest but retains the host',
    () async {
      const config = GoConfig();
      final server = LanHostServer(
        authority: LanAuthority(config),
        token: 'room-pin',
      );
      final host = LanClientConnection(config);
      final guest = LanClientConnection(config);
      addTearDown(() async {
        await guest.close();
        await host.close();
        await server.close();
      });
      await server.start(host: '127.0.0.1', port: 0);
      await host.connectHost(server);
      await guest.connect(
        Uri.parse('ws://127.0.0.1:${server.port}'),
        token: server.token,
      );
      expect(server.playerCount, 2);
      final guestGone = server.playerCounts.firstWhere((count) => count == 1);
      // Like Android suspending the Dart isolate: wall time advances while all
      // heartbeat callbacks and socket messages wait for the same event loop.
      sleep(const Duration(seconds: 21));
      await guestGone.timeout(const Duration(seconds: 5));
      expect(server.playerCount, 1);
      expect(host.side, Side.black);
      await guest.reconnect();
      expect(server.playerCount, 2);
      final started = host.messages.firstWhere(
        (message) => message.type == LanMessageType.matchStart,
      );
      server.startMatch();
      await started;
      expect(host.started, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  for (final game in ['go', 'chess', 'xiangqi', 'gomoku', 'draughts']) {
    test('$game host survives suspension, admits a guest and starts', () {
      fakeAsync((time) {
        const config = GoConfig();
        final server = LanHostServer(
          authority: game == 'go' ? LanAuthority(config) : null,
          chessAuthority: game == 'chess' ? ChessAuthority() : null,
          xiangqiAuthority: game == 'xiangqi' ? XiangqiAuthority() : null,
          gomokuAuthority: game == 'gomoku' ? GomokuLanAuthority() : null,
          draughtsAuthority: game == 'draughts'
              ? DraughtsAuthority(DraughtsVariant.international)
              : null,
          token: 'room-pin',
        );
        final host = switch (game) {
          'chess' => LanClientConnection.chess(),
          'xiangqi' => LanClientConnection.xiangqi(),
          'gomoku' => LanClientConnection.gomoku(),
          'draughts' => LanClientConnection.draughts(
            DraughtsVariant.international,
          ),
          _ => LanClientConnection(config),
        };
        var ready = false;
        host.connectHost(server).then((_) => ready = true);
        time.flushMicrotasks();
        expect(ready, isTrue);
        expect(host.side, server.coordinator.firstSide);
        expect(server.playerCount, 1);
        // No local deadline may run ahead of a delayed local pong on resume.
        expect(time.periodicTimerCount, 0);
        time.elapseBlocking(const Duration(minutes: 5));
        time.elapse(const Duration(seconds: 5));
        expect(server.playerCount, 1);
        expect(host.started, isFalse);

        final guest = RtcMatchClient(
          RtcInvitation.offer(
            game,
            'v=0',
            variant: game == 'draughts' ? DraughtsVariant.international : null,
          ),
        );
        final (authority, client) = MemoryTransport.pair();
        server.coordinator.attach(authority);
        guest.bind(client, token: server.token);
        time.flushMicrotasks();
        expect(guest.side, host.side!.opponent);
        expect(server.playerCount, 2);
        server.startMatch();
        time.flushMicrotasks();
        expect(host.started && guest.started, isTrue);
        host.send(
          LanMessage(LanMessageType.resign, 1, {
            'side': LanMessage.sideCode(host.side!),
          }),
        );
        time.flushMicrotasks();
        expect(server.gameOver, isTrue);
        expect(host.seq, guest.seq);
        guest.close();
        host.close();
        server.close();
        time.flushMicrotasks();
        expect(time.pendingTimers, isEmpty);
      });
    });
  }
}
