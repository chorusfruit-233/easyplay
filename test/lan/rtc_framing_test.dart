import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/lan/lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/rtc_framing.dart';

LanMessage syncWith(String padding) {
  final sync = LanAuthority(
    const GoConfig(),
  ).sync(LanMessage(LanMessageType.stateRequest, 0, {'lastSeq': 0}));
  return LanMessage(sync.type, sync.seq, {...sync.body, 'padding': padding});
}

void main() {
  test(
    'UTF-8 fragments respect SCTP limit and reassemble in reverse order',
    () {
      final message = syncWith('棋局🙂' * 20000);
      final frames = rtcFrames(message, maxFrameBytes: 4096).toList();
      expect(frames.length, greaterThan(1));
      expect(frames.every((f) => utf8.encode(f).length <= 4096), isTrue);
      final receiver = RtcReassembler();
      LanMessage? received;
      for (final frame in frames.reversed) {
        received = receiver.receive(frame) ?? received;
      }
      expect(received!.encode(), message.encode());
      expect(receiver.pendingCount, 0);
    },
  );
  test(
    'reject duplicate, forged digest, bad lengths and oversized messages',
    () {
      final frames = rtcFrames(syncWith('棋' * 20000)).toList();
      final receiver = RtcReassembler();
      receiver.receive(frames.first);
      expect(() => receiver.receive(frames.first), throwsFormatException);
      expect(receiver.pendingCount, 0);
      final altered = jsonDecode(frames.last) as Map<String, dynamic>;
      altered['digest'] = '0' * 64;
      for (final frame in frames.take(frames.length - 1)) {
        receiver.receive(frame);
      }
      expect(
        () => receiver.receive(jsonEncode(altered)),
        throwsFormatException,
      );
      expect(receiver.pendingCount, 0);
      altered['byteLength'] = rtcMaxMessageBytes + 1;
      expect(
        () => receiver.receive(jsonEncode(altered)),
        throwsFormatException,
      );
      expect(
        () => rtcFrames(syncWith('x' * rtcMaxMessageBytes)).toList(),
        throwsFormatException,
      );
    },
  );
  test('lost fragments expire and incomplete memory is bounded', () {
    final receiver = RtcReassembler();
    final frame = rtcFrames(syncWith('x' * 20000)).first;
    receiver.receive(frame);
    expect(
      receiver.expire(DateTime.now().add(const Duration(seconds: 16))),
      isTrue,
    );
    expect(receiver.pendingCount, 0);
    for (var i = 0; i < 4; i++) {
      receiver.receive(rtcFrames(syncWith('x' * 20000)).first);
    }
    expect(
      () => receiver.receive(rtcFrames(syncWith('x' * 20000)).first),
      throwsFormatException,
    );
    expect(receiver.pendingCount, 4);
    receiver.clear();
    expect(receiver.reservedBytes, 0);
  });
}
