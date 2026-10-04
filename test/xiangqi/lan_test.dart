import 'package:easyplay/game_session.dart';
import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:easyplay/lan/xiangqi_lan_game.dart';
import 'package:easyplay/lan/chess_lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/room_coordinator.dart';
import 'package:easyplay/lan/rtc_manual_signaling.dart';
import 'package:easyplay/lan/lan_transport.dart';
import 'package:flutter_test/flutter_test.dart';

LanMessage move(int seq, Side side, String uci, {String game = 'xiangqi'}) =>
    LanMessage(LanMessageType.move, seq, {
      'side': LanMessage.sideCode(side),
      'game': game,
      'move': uci,
    });
void main() {
  test('reconnect restores the repetition cycle before its final verdict', () {
    final host = XiangqiAuthority();
    const moves = ['b0a2', 'b9a7', 'a2b0', 'a7b9', 'b0a2', 'b9a7', 'a2b0'];
    for (var i = 0; i < moves.length; i++) {
      final side = i.isEven ? Side.white : Side.black;
      expect(
        host.submit(side, move(i + 1, side, moves[i])).type,
        LanMessageType.move,
      );
    }
    final restored = XiangqiLanReplica();
    expect(restored.receive(host.sync(restored.stateRequest())), isTrue);
    expect(restored.session.repetitionHistory.length, 7);
    final last = host.submit(Side.black, move(8, Side.black, 'a7b9'));
    expect(restored.receive(last), isTrue);
    expect(restored.session.result, host.session.result);
    expect(restored.session.result!.reason, XiangqiEndReason.repetitionDraw);
  });
  test('malformed sync is atomic and malformed move does not advance seq', () {
    final host = XiangqiAuthority(), replica = XiangqiLanReplica();
    expect(() => move(1, Side.white, 'garbage'), throwsFormatException);
    expect(host.seq, 0);
    final bad = LanMessage(LanMessageType.stateSync, 1, {
      'game': 'xiangqi',
      'rulesVersion': 1,
      'ruleProfile': 'asian',
      'roomVersion': lanProtocolVersion,
      'events': [move(1, Side.white, 'a0a9').toWire()],
    });
    expect(replica.receive(bad), isFalse);
    expect(replica.seq, 0);
    expect(replica.session.fen, XiangqiSession().fen);
  });
  test('Xiangqi parser accepts rank zero and rejects chess promotions', () {
    expect(
      LanMessage.decode(move(1, Side.white, 'a0a1').encode()).body['move'],
      'a0a1',
    );
    expect(
      () => LanMessage.decode(move(1, Side.white, 'a0a1q').encode()),
      throwsFormatException,
    );
    expect(
      () => LanMessage.decode(
        move(1, Side.white, 'a0a1', game: 'chess').encode(),
      ),
      throwsFormatException,
    );
    expect(
      ChessAuthority().submit(Side.white, move(1, Side.white, 'e2e4')).type,
      LanMessageType.rejected,
    );
  });
  test(
    'red first, strict hello profile and rejected moves never advance seq',
    () async {
      final authority = XiangqiAuthority();
      final room = RoomCoordinator(xiangqiAuthority: authority, token: '1234');
      expect(room.firstSide, Side.white);
      expect(
        room.acceptsHello({
          'game': 'xiangqi',
          'rulesVersion': 1,
          'ruleProfile': 'asian',
        }),
        isTrue,
      );
      expect(
        room.acceptsHello({
          'game': 'xiangqi',
          'rulesVersion': 1,
          'ruleProfile': 'unknown',
        }),
        isFalse,
      );
      expect(
        authority.submit(Side.black, move(1, Side.black, 'a9a8')).type,
        LanMessageType.rejected,
      );
      expect(
        authority.submit(Side.white, move(1, Side.white, 'a0a9')).type,
        LanMessageType.rejected,
      );
      expect(authority.seq, 0);
      expect(
        authority.submit(Side.white, move(1, Side.white, 'h2e2')).type,
        LanMessageType.move,
      );
      expect(authority.session.turn, XiangqiSide.black);
      expect(
        authority.submit(Side.white, move(1, Side.white, 'h2e2')).type,
        LanMessageType.rejected,
      );
      await room.close();
    },
  );
  test('sync replays all moves, negotiations and rounds atomically', () {
    final authority = XiangqiAuthority();
    final replica = XiangqiLanReplica();
    void send(
      Side side,
      LanMessageType type, [
      Map<String, Object?> body = const {},
    ]) {
      final event = authority.submit(
        side,
        LanMessage(type, authority.seq + 1, {
          'side': LanMessage.sideCode(side),
          ...body,
        }),
      );
      expect(event.type, type);
      expect(replica.receive(event), isTrue);
    }

    send(Side.white, LanMessageType.move, {'game': 'xiangqi', 'move': 'h2e2'});
    send(Side.white, LanMessageType.undoRequest);
    send(Side.black, LanMessageType.undoAccept, {'requestSeq': 2});
    expect(replica.session.moves, isEmpty);
    send(Side.white, LanMessageType.drawRequest);
    send(Side.black, LanMessageType.drawAccept, {'requestSeq': 4});
    expect(replica.session.result!.reason, XiangqiEndReason.drawAgreement);
    send(Side.black, LanMessageType.rematchRequest);
    send(Side.white, LanMessageType.rematchAccept, {'requestSeq': 6});
    expect(replica.round, 2);
    send(Side.white, LanMessageType.move, {'game': 'xiangqi', 'move': 'b0c2'});
    final restored = XiangqiLanReplica();
    expect(restored.receive(authority.sync(restored.stateRequest())), isTrue);
    expect(restored.session.fen, replica.session.fen);
    expect(restored.session.repetitionHistory.length, 1);
    expect(restored.round, 2);
    expect(restored.seq, 8);
  });
  test('LAN sockets wait for start and recover the complete history', () async {
    final host = LanHostServer(
      xiangqiAuthority: XiangqiAuthority(),
      token: '1234',
    );
    final red = LanClientConnection.xiangqi(),
        black = LanClientConnection.xiangqi();
    try {
      await host.start();
      final uri = Uri.parse('ws://127.0.0.1:${host.port}');
      await red.connect(uri, token: '1234');
      await black.connect(uri, token: '1234');
      expect(red.side, Side.white);
      expect(black.side, Side.black);
      expect(black.started, isFalse);
      host.startMatch();
      final committed = black.messages.firstWhere(
        (m) => m.type == LanMessageType.move,
      );
      red.send(move(1, Side.white, 'h2e2'));
      await committed;
      await black.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await black.reconnect();
      expect(
        black.xiangqiReplica!.session.fen,
        red.xiangqiReplica!.session.fen,
      );
      expect(black.xiangqiReplica!.session.repetitionHistory.length, 1);
    } finally {
      await red.close();
      await black.close();
      await host.close();
    }
  });
  test('RTC invitation pins the Asian rule configuration', () {
    final invitation = RtcInvitation.offer('xiangqi', 'v=0\r\n');
    final decoded = RtcInvitation.decode(invitation.encode());
    expect(decoded.configuration['ruleProfile'], 'asian');
    expect(decoded.configuration['rulesVersion'], 1);
  });
}
