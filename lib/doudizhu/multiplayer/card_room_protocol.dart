import '../../lan/lan_protocol.dart';
export '../../lan/lan_protocol.dart' show LanMessage, LanMessageType;

LanMessage cardMessage(String action, int seq, Map<String, Object?> payload) =>
    LanMessage(LanMessageType.card, seq, {
      'game': 'doudizhu',
      'protocolVersion': 1,
      'rulesVersion': 1,
      'action': action,
      'payload': payload,
    });
Map<String, Object?> cardPayload(LanMessage m) =>
    Map<String, Object?>.from(m.body['payload'] as Map);
