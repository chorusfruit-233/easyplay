import '../game_session.dart' show Side;

/// Both players are local AIs; difficulty follows the side, including variants
/// in which White makes the first move.
class AiDuelConfig<L extends Enum> {
  const AiDuelConfig({required this.blackLevel, required this.whiteLevel});

  final L blackLevel;
  final L whiteLevel;

  L levelFor(Side side) => side == Side.black ? blackLevel : whiteLevel;

  Map<String, Object?> toJson() => {
    'blackLevel': blackLevel.name,
    'whiteLevel': whiteLevel.name,
  };

  static AiDuelConfig<L> fromJson<L extends Enum>(
    Object? json,
    List<L> levels,
  ) {
    if (json is! Map) throw const FormatException('缺少 AI 对抗设置');
    final black = levels.where((v) => v.name == json['blackLevel']).firstOrNull;
    final white = levels.where((v) => v.name == json['whiteLevel']).firstOrNull;
    if (black == null || white == null) {
      throw const FormatException('无效的 AI 对抗难度');
    }
    return AiDuelConfig(blackLevel: black, whiteLevel: white);
  }
}
