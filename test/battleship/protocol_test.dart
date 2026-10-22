import 'dart:convert';

import 'package:easyplay/battleship/multiplayer/battleship_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Battleship has a dedicated typed envelope with strict versions', () {
    final message = battleshipMessage('fire', 3, {'cell': 42});
    final decoded = LanMessage.decode(message.encode());
    expect(decoded.type, LanMessageType.battleship);
    expect(decoded.seq, 3);
    expect(battleshipPayload(decoded), {'cell': 42});
    for (final change in <Map<String, Object?>>[
      {'game': 'doudizhu'},
      {'protocolVersion': 2},
      {'protocolVersion': 1.0},
      {'rulesVersion': 2},
      {'rulesVersion': 1.0},
      {'action': ''},
      {'action': 3},
      {'action': 'x' * 33},
      {'payload': []},
    ]) {
      expect(
        () => LanMessage.decode(jsonEncode({...message.toWire(), ...change})),
        throwsFormatException,
      );
    }
    expect(
      () => battleshipMessage('snapshot', 1, {'text': '海' * 23000}),
      throwsFormatException,
    );
    expect(
      () => battleshipMessage('snapshot', 1, {'text': 'a' * 65500}),
      throwsFormatException,
    );
    expect(
      () => LanMessage.decode('${' ' * 65536}${message.encode()}'),
      throwsFormatException,
    );
  });
}
