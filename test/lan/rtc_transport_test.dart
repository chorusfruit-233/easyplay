import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/lan/lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/rtc_channel.dart';
import 'package:easyplay/lan/rtc_framing.dart';

class Channel implements RtcTextChannel {
  final incomingController = StreamController<String>.broadcast();
  final disconnectController = StreamController<void>.broadcast();
  Channel? other;
  Completer<void>? gate;
  @override
  int get maxMessageSize => 4096;
  @override
  Stream<String> get incoming => incomingController.stream;
  @override
  Stream<void> get disconnections => disconnectController.stream;
  @override
  Future<void> sendText(String raw) async {
    if (gate != null) {
      final waiting = gate!;
      gate = null;
      await waiting.future;
    }
    other!.incomingController.add(raw);
  }

  @override
  Future<void> close() async {
    await incomingController.close();
    await disconnectController.close();
  }
}

void main() {
  test('retains messages received before room subscribes', () async {
    final channel = Channel();
    final receiver = RtcMessageTransport(channel);
    final early = LanMessage(LanMessageType.ping, 0, {'nonce': 'early'});
    try {
      for (final frame in rtcFrames(early)) {
        channel.incomingController.add(frame);
      }
      // The DataChannel delivers before the room attaches its listener.
      await Future<void>.delayed(Duration.zero);
      final received = await receiver.messages.first.timeout(
        const Duration(milliseconds: 200),
      );
      expect(received.encode(), early.encode());
    } finally {
      await receiver.close();
    }
  });

  test('pre-subscription queue rejects excess messages', () async {
    final channel = Channel();
    final receiver = RtcMessageTransport(channel);
    try {
      final message = LanMessage(LanMessageType.ping, 0, {'nonce': 'early'});
      for (var i = 0; i < 65; i++) {
        for (final frame in rtcFrames(message)) {
          channel.incomingController.add(frame);
        }
      }
      await Future<void>.delayed(Duration.zero);
      await expectLater(receiver.messages.first, throwsFormatException);
    } finally {
      await receiver.close();
    }
  });
  test(
    'queued sync yields to control messages while channel applies backpressure',
    () async {
      final a = Channel(), b = Channel();
      a.other = b;
      b.other = a;
      final gate = Completer<void>();
      a.gate = gate;
      final sender = RtcMessageTransport(a), receiver = RtcMessageTransport(b);
      final received = <LanMessage>[];
      final ready = Completer<void>();
      final sub = receiver.messages.listen((m) {
        received.add(m);
        if (received.length == 2) ready.complete();
      });
      final sync = LanAuthority(
        const GoConfig(),
      ).sync(LanMessage(LanMessageType.stateRequest, 0, {'lastSeq': 0}));
      sender.send(
        LanMessage(sync.type, sync.seq, {...sync.body, 'padding': '局' * 30000}),
      );
      sender.send(LanMessage(LanMessageType.ping, 0, {'nonce': 'control'}));
      expect(received, isEmpty);
      gate.complete();
      await ready.future.timeout(const Duration(seconds: 5));
      expect(received.map((m) => m.type), [
        LanMessageType.ping,
        LanMessageType.stateSync,
      ]);
      await sub.cancel();
      await sender.close();
      await receiver.close();
    },
  );
}
