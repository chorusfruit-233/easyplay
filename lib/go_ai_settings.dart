import 'dart:math';

import 'game_session.dart';

enum GoOpponentMode { kataGo, local }

enum GoPlayerColor { black, white, random }

/// Playable ranks on KataGo's human-SL scale, weakest first. 20k..1k are kyu,
/// 1d..9d are dan; the numeric form uses 20..1 for kyu and 0..-8 for dan,
/// matching the reference app's scale.
enum GoAiRank {
  k20('20k', 20),
  k19('19k', 19),
  k18('18k', 18),
  k17('17k', 17),
  k16('16k', 16),
  k15('15k', 15),
  k14('14k', 14),
  k13('13k', 13),
  k12('12k', 12),
  k11('11k', 11),
  k10('10k', 10),
  k9('9k', 9),
  k8('8k', 8),
  k7('7k', 7),
  k6('6k', 6),
  k5('5k', 5),
  k4('4k', 4),
  k3('3k', 3),
  k2('2k', 2),
  k1('1k', 1),
  d1('1d', 0),
  d2('2d', -1),
  d3('3d', -2),
  d4('4d', -3),
  d5('5d', -4),
  d6('6d', -5),
  d7('7d', -6),
  d8('8d', -7),
  d9('9d', -8),
  strongest('Max', -9);

  final String label;
  final int humanRank;
  const GoAiRank(this.label, this.humanRank);

  /// Baseline search budget for one move when not playing human style.
  ///
  /// Deliberately flat: on a phone this is roughly 20-50 visits per second on
  /// two threads, so a per-rank curve into the thousands would mean minutes per
  /// move. Rank-dependent tuning belongs to the engine's override rules, whose
  /// `maxVisits` merges later and therefore wins over this baseline.
  int get maxVisits => this == GoAiRank.strongest ? 10000 : 120;

  /// Ranks a model of the given reach can offer. The bundled b6 is a small v8
  /// network that cannot back the upper dan labels, so it stops at 5d.
  static List<GoAiRank> availableFor({required int highestHumanRank}) => [
    for (final value in GoAiRank.values)
      if (value == GoAiRank.strongest || value.humanRank >= highestHumanRank)
        value,
  ];
}

enum GoAiStyle { modern, traditional, human }

extension GoAiStyleX on GoAiStyle {
  String get label => switch (this) {
    GoAiStyle.modern => '现代',
    GoAiStyle.traditional => '传统',
    GoAiStyle.human => '人类棋风',
  };
}

class GoAiSettings {
  final GoOpponentMode opponentMode;
  final GoPlayerColor playerColor;
  final GoAiRank rank;
  final GoAiStyle style;
  final String modelId;
  final String engineProfileId;
  final String? humanModelId;

  /// Explicit KataGo human-style rank. When omitted, [rank.humanRank] is used.
  final int? humanStyleRank;

  /// Optional named humanSL profile supplied by KataGo or an override file.
  final String? humanSLProfile;

  const GoAiSettings({
    this.opponentMode = GoOpponentMode.kataGo,
    this.playerColor = GoPlayerColor.black,
    this.rank = GoAiRank.k5,
    this.style = GoAiStyle.modern,
    this.modelId = 'b6',
    this.engineProfileId = 'default',
    this.humanModelId,
    this.humanStyleRank,
    this.humanSLProfile,
  });

  Side resolvePlayerSide({Random? random}) => switch (playerColor) {
    GoPlayerColor.black => Side.black,
    GoPlayerColor.white => Side.white,
    GoPlayerColor.random =>
      (random ?? Random()).nextBool() ? Side.black : Side.white,
  };

  GoAiSettings copyWith({
    GoOpponentMode? opponentMode,
    GoPlayerColor? playerColor,
    GoAiRank? rank,
    GoAiStyle? style,
    String? modelId,
    String? engineProfileId,
    String? humanModelId,
    int? humanStyleRank,
    String? humanSLProfile,
  }) => GoAiSettings(
    opponentMode: opponentMode ?? this.opponentMode,
    playerColor: playerColor ?? this.playerColor,
    rank: rank ?? this.rank,
    style: style ?? this.style,
    modelId: modelId ?? this.modelId,
    engineProfileId: engineProfileId ?? this.engineProfileId,
    humanModelId: humanModelId ?? this.humanModelId,
    humanStyleRank: humanStyleRank ?? this.humanStyleRank,
    humanSLProfile: humanSLProfile ?? this.humanSLProfile,
  );

  Map<String, Object> toJson() => {
    'opponentMode': opponentMode.name,
    'playerColor': playerColor.name,
    'rank': rank.name,
    'style': style.name,
    'modelId': modelId,
    'engineProfileId': engineProfileId,
    'humanModelId': ?humanModelId,
    'humanStyleRank': ?humanStyleRank,
    'humanSLProfile': ?humanSLProfile,
  };

  factory GoAiSettings.fromJson(Map<String, Object?> json) => GoAiSettings(
    opponentMode: json['opponentMode'] == GoOpponentMode.kataGo.name
        ? GoOpponentMode.kataGo
        : GoOpponentMode.local,
    playerColor: GoPlayerColor.values.firstWhere(
      (value) => value.name == json['playerColor'],
      orElse: () => GoPlayerColor.black,
    ),
    rank: _rankFromName(json['rank'] as String?),
    style: GoAiStyle.values.firstWhere(
      (value) => value.name == json['style'],
      orElse: () => GoAiStyle.modern,
    ),
    modelId: json['modelId'] as String? ?? 'b6',
    engineProfileId: json['engineProfileId'] as String? ?? 'default',
    humanModelId: json['humanModelId'] as String?,
    humanStyleRank: json['humanStyleRank'] as int?,
    humanSLProfile: json['humanSLProfile'] as String?,
  );

  int get resolvedHumanStyleRank => humanStyleRank ?? rank.humanRank;

  bool get usesHumanStyle => style == GoAiStyle.human;

  static String humanRankLabel(int rank) =>
      rank > 0 ? '${rank}k' : '${1 - rank}d';

  String get resolvedHumanSLProfile => humanSLProfile?.trim().isNotEmpty == true
      ? humanSLProfile!.trim()
      : 'rank_${humanRankLabel(resolvedHumanStyleRank)}';

  /// Restores a rank from storage.
  ///
  /// The enum went from seven coarse presets to the full 20k..9d scale, so the
  /// old member names no longer exist. Without this mapping a stored 'beginner'
  /// or 'strongest' would silently collapse to the middle preset.
  static GoAiRank _rankFromName(String? name) {
    const legacy = <String, GoAiRank>{
      'beginner': GoAiRank.k20,
      'club': GoAiRank.k10,
      'intermediate': GoAiRank.k5,
      'advanced': GoAiRank.k1,
      'dan1': GoAiRank.d1,
      'dan5': GoAiRank.d5,
      'strongest': GoAiRank.strongest,
    };
    final restored = legacy[name];
    if (restored != null) return restored;
    return GoAiRank.values.firstWhere(
      (value) => value.name == name,
      orElse: () => GoAiRank.k5,
    );
  }

  void validateHumanStyle() {
    if (!usesHumanStyle) return;
    if (resolvedHumanStyleRank < -8 || resolvedHumanStyleRank > 20) {
      throw ArgumentError('人类棋风段位必须在 20k 至 9d 之间');
    }
    if (!RegExp(
      r'^(rank|preaz)_(?:[1-9]d|(?:[1-9]|1[0-9]|20)k)(?:_(?:[1-9]d|(?:[1-9]|1[0-9]|20)k))?$',
    ).hasMatch(resolvedHumanSLProfile)) {
      throw ArgumentError('humanSLProfile 应为 rank_5k、preaz_5d 等有效段位配置');
    }
    if (humanModelId == null) {
      throw ArgumentError('人类棋风需要在引擎中配置独立的人类棋风模型');
    }
  }
}
