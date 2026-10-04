import '../xiangqi/xiangqi_session.dart'
    show xiangqiRulesVersion, xiangqiRuleProfile;
import 'dart:convert';

import '../game_session.dart';
import '../gomoku/gomoku_session.dart' show GomokuVariant;
import '../draughts/draughts_variant.dart';
import '../draughts/draughts_session.dart' show draughtsRulesVersion;
import '../chess/chess_session.dart' show chessRulesVersion;
import 'lan_protocol.dart';
import 'rtc_framing.dart';

class RtcInvitation {
  RtcInvitation({
    required this.sessionId,
    required this.token,
    required this.game,
    this.variant,
    this.gomokuVariant = GomokuVariant.freestyle,
    this.goConfig = const GoConfig(),
    required this.type,
    required this.sdp,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();
  final String sessionId, token, game, type, sdp;
  final DraughtsVariant? variant;
  final GomokuVariant gomokuVariant;
  final GoConfig goConfig;
  final DateTime createdAt;
  static const maxBytes = 256 * 1024;
  Map<String, Object?> get configuration => {
    'game': game,
    if (game == 'go') ...LanMessage.configToWire(goConfig),
    if (game == 'xiangqi') ...{
      'rulesVersion': xiangqiRulesVersion,
      'ruleProfile': xiangqiRuleProfile,
    },
    if (game == 'chess') 'rulesVersion': chessRulesVersion,
    if (game == 'gomoku') ...LanMessage.gomokuConfigToWire(gomokuVariant),
    if (game == 'draughts') ...{
      'variant': variant!.name,
      'rulesVersion': draughtsRulesVersion,
    },
  };
  String encode() {
    final encoded = jsonEncode({
      'formatVersion': 1,
      'sessionId': sessionId,
      'token': token,
      'createdAt': createdAt.toIso8601String(),
      ...configuration,
      'description': {'type': type, 'sdp': sdp},
    });
    if (utf8.encode(encoded).length > maxBytes) {
      throw const FormatException('邀请信息过长，请更换网络后重新创建');
    }
    return encoded;
  }

  RtcInvitation answer(String sdp) => RtcInvitation(
    sessionId: sessionId,
    token: token,
    game: game,
    variant: variant,
    gomokuVariant: gomokuVariant,
    goConfig: goConfig,
    type: 'answer',
    sdp: sdp,
    createdAt: createdAt,
  );

  static RtcInvitation decode(
    String raw, {
    String? expectedType,
    DateTime? now,
  }) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('邀请信息过长');
    }
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['formatVersion'] is! int ||
        data['formatVersion'] != 1) {
      throw const FormatException('邀请格式版本不支持');
    }
    for (final field in ['sessionId', 'token']) {
      if (data[field] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(data[field] as String)) {
        throw const FormatException('邀请身份无效');
      }
    }
    final at = data['createdAt'] is String
        ? DateTime.tryParse(data['createdAt'] as String)
        : null;
    final clock = now ?? DateTime.now();
    if (at == null ||
        clock.difference(at) > const Duration(minutes: 30) ||
        at.difference(clock) > const Duration(minutes: 2)) {
      throw const FormatException('邀请已过期或时间无效，请重新创建');
    }
    final description = data['description'];
    if (description is! Map ||
        !['offer', 'answer'].contains(description['type']) ||
        (expectedType != null && description['type'] != expectedType) ||
        description['sdp'] is! String ||
        !(description['sdp'] as String).startsWith('v=0') ||
        (description['sdp'] as String).length > maxBytes) {
      throw const FormatException('邀请描述无效');
    }
    final game = data['game'];
    if (!['go', 'chess', 'draughts', 'gomoku', 'xiangqi'].contains(game)) {
      throw const FormatException('不支持的棋种');
    }
    if (game == 'xiangqi') {
      LanMessage.validateXiangqiConfig(Map<String, Object?>.from(data));
    }
    final gomokuVariant = game == 'gomoku'
        ? LanMessage.parseGomokuVariant(Map<String, Object?>.from(data))
        : GomokuVariant.freestyle;
    DraughtsVariant? variant;
    if (game == 'draughts') {
      for (final item in DraughtsVariant.values) {
        if (item.name == data['variant']) variant = item;
      }
      if (variant == null ||
          data['rulesVersion'] is! int ||
          data['rulesVersion'] != draughtsRulesVersion) {
        throw const FormatException('跳棋规则版本不兼容');
      }
    }
    if (game == 'chess' &&
        (data['rulesVersion'] is! int ||
            data['rulesVersion'] != chessRulesVersion)) {
      throw const FormatException('国际象棋规则版本不兼容');
    }
    return RtcInvitation(
      sessionId: data['sessionId'] as String,
      token: data['token'] as String,
      game: game as String,
      variant: variant,
      gomokuVariant: gomokuVariant,
      goConfig: game == 'go'
          ? LanMessage.parseConfig(Map<String, Object?>.from(data))
          : const GoConfig(),
      type: description['type'] as String,
      sdp: description['sdp'] as String,
      createdAt: at,
    );
  }

  void validateAnswer(RtcInvitation response) {
    if (response.type != 'answer' ||
        response.sessionId != sessionId ||
        response.token != token ||
        jsonEncode(response.configuration) != jsonEncode(configuration)) {
      throw const FormatException('回应不属于当前房间');
    }
  }

  static RtcInvitation offer(
    String game,
    String sdp, {
    DraughtsVariant? variant,
    GomokuVariant gomokuVariant = GomokuVariant.freestyle,
    GoConfig config = const GoConfig(),
  }) => RtcInvitation(
    sessionId: rtcSecret(),
    token: rtcSecret(),
    game: game,
    variant: variant,
    gomokuVariant: gomokuVariant,
    goConfig: config,
    type: 'offer',
    sdp: sdp,
  );
}
