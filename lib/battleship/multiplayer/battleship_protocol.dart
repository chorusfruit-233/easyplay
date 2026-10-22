import '../../lan/lan_protocol.dart';

export '../../lan/lan_protocol.dart' show LanMessage, LanMessageType;

LanMessage battleshipMessage(
  String action,
  int seq,
  Map<String, Object?> payload,
) => LanMessage(LanMessageType.battleship, seq, {
  'game': 'battleship',
  'protocolVersion': 1,
  'rulesVersion': 1,
  'action': action,
  'payload': payload,
});

Map<String, Object?> battleshipPayload(LanMessage message) =>
    Map<String, Object?>.from(message.body['payload'] as Map);
