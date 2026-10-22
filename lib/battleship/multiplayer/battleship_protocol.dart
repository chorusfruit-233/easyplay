import '../../lan/lan_protocol.dart';
import '../battleship_model.dart' show battleshipRulesVersion;

export '../../lan/lan_protocol.dart' show LanMessage, LanMessageType;

LanMessage battleshipMessage(
  String action,
  int seq,
  Map<String, Object?> payload,
) => LanMessage(LanMessageType.battleship, seq, {
  'game': 'battleship',
  'protocolVersion': 1,
  'rulesVersion': battleshipRulesVersion,
  'action': action,
  'payload': payload,
});

Map<String, Object?> battleshipPayload(LanMessage message) =>
    Map<String, Object?>.from(message.body['payload'] as Map);
