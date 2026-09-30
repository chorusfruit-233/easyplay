import 'dart:async';

import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/game_session.dart' show GoConfig;
import 'package:easyplay/lan/chess_lan_game.dart';
import 'package:easyplay/lan/draughts_lan_game.dart';
import 'package:easyplay/lan/lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_transport.dart';

/// Runs the real authority/replica rules while keeping widget tests off sockets.
class FakeLanConnection extends LanClientConnection {
  FakeLanConnection.chess(Side localSide)
    : authority = LanHostServer(
        chessAuthority: ChessAuthority(),
        token: 'test',
      ),
      super.chess() {
    chessReplica = ChessLanReplica();
    side = localSide;
    started = true;
  }
  FakeLanConnection.draughts(DraughtsVariant variant, Side localSide)
    : authority = LanHostServer(
        draughtsAuthority: DraughtsAuthority(variant),
        token: 'test',
      ),
      super.draughts(variant) {
    draughtsReplica = DraughtsLanReplica(variant);
    side = localSide;
    started = true;
  }
  FakeLanConnection.go(Side localSide)
    : authority = LanHostServer(
        authority: LanAuthority(const GoConfig(boardSize: 9)),
        token: 'test',
      ),
      super(const GoConfig(boardSize: 9)) {
    replica = LanReplica(config);
    side = localSide;
    started = true;
  }

  final LanHostServer authority;
  final sent = <LanMessage>[];
  final _events = StreamController<LanMessage>.broadcast();
  @override
  Stream<LanMessage> get messages => _events.stream;

  @override
  void send(LanMessage message) {
    sent.add(message);
    _receive(authority.submit(side!, message));
  }

  void commit(
    Side player,
    LanMessageType type, [
    Map<String, Object?> body = const {},
  ]) => _receive(
    authority.submit(
      player,
      LanMessage(type, seq + 1, {'side': LanMessage.sideCode(player), ...body}),
    ),
  );

  void _receive(LanMessage event) {
    if (event.type != LanMessageType.rejected) {
      final accepted =
          chessReplica?.receive(event) ??
          draughtsReplica?.receive(event) ??
          replica!.receive(event);
      if (!accepted) throw StateError('Replica rejected ${event.type}');
    }
    _events.add(event);
  }

  @override
  Future<void> close() async {}

  Future<void> dispose() async {
    await _events.close();
    chessReplica?.dispose();
    await authority.close();
  }
}
