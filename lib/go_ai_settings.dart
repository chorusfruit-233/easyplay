import 'dart:math';

import 'game_session.dart';

enum GoOpponentMode { kataGo, local }

enum GoPlayerColor { black, white, random }

enum GoAiRank {
  beginner('20k', 48),
  club('10k', 120),
  intermediate('5k', 500),
  advanced('1k', 1200),
  dan1('1d', 2500),
  dan5('5d', 5000),
  strongest('最强', 10000);

  final String label;
  final int maxVisits;
  const GoAiRank(this.label, this.maxVisits);
}

enum GoAiStyle { modern, traditional, human }

extension GoAiStyleX on GoAiStyle {
  String get label => switch (this) {
    GoAiStyle.modern => '现代',
    GoAiStyle.traditional => '传统',
    GoAiStyle.human => '人类棋风',
  };
}

extension GoAiRankX on GoAiRank {
  /// Reference app's rank scale: 20k=20, 1k=1, 1d=0, 9d=-8.
  int get humanRank => switch (this) {
    GoAiRank.beginner => 20,
    GoAiRank.club => 10,
    GoAiRank.intermediate => 5,
    GoAiRank.advanced => 1,
    GoAiRank.dan1 => 0,
    GoAiRank.dan5 => -4,
    GoAiRank.strongest => -8,
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
  final bool useBuiltinHumanStyle;

  const GoAiSettings({
    this.opponentMode = GoOpponentMode.kataGo,
    this.playerColor = GoPlayerColor.black,
    this.rank = GoAiRank.intermediate,
    this.style = GoAiStyle.modern,
    this.modelId = 'b6',
    this.engineProfileId = 'default',
    this.humanModelId,
    this.humanStyleRank,
    this.humanSLProfile,
    this.useBuiltinHumanStyle = false,
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
    bool? useBuiltinHumanStyle,
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
    useBuiltinHumanStyle: useBuiltinHumanStyle ?? this.useBuiltinHumanStyle,
  );

  Map<String, Object> toJson() => {
    'opponentMode': opponentMode.name,
    'playerColor': playerColor.name,
    'rank': rank.name,
    'style': style.name,
    'modelId': modelId,
    'engineProfileId': engineProfileId,
    if (humanModelId != null) 'humanModelId': humanModelId!,
    if (humanStyleRank != null) 'humanStyleRank': humanStyleRank!,
    if (humanSLProfile != null) 'humanSLProfile': humanSLProfile!,
    'useBuiltinHumanStyle': useBuiltinHumanStyle,
  };

  factory GoAiSettings.fromJson(Map<String, Object?> json) => GoAiSettings(
    opponentMode: json['opponentMode'] == GoOpponentMode.kataGo.name
        ? GoOpponentMode.kataGo
        : GoOpponentMode.local,
    playerColor: GoPlayerColor.values.firstWhere(
      (value) => value.name == json['playerColor'],
      orElse: () => GoPlayerColor.black,
    ),
    rank: GoAiRank.values.firstWhere(
      (value) => value.name == json['rank'],
      orElse: () => GoAiRank.intermediate,
    ),
    style: GoAiStyle.values.firstWhere(
      (value) => value.name == json['style'],
      orElse: () => GoAiStyle.modern,
    ),
    modelId: json['modelId'] as String? ?? 'b6',
    engineProfileId: json['engineProfileId'] as String? ?? 'default',
    humanModelId: json['humanModelId'] as String?,
    humanStyleRank: json['humanStyleRank'] as int?,
    humanSLProfile: json['humanSLProfile'] as String?,
    useBuiltinHumanStyle: json['useBuiltinHumanStyle'] as bool? ?? false,
  );

  int get resolvedHumanStyleRank => humanStyleRank ?? rank.humanRank;

  bool get usesHumanStyle => style == GoAiStyle.human;

  static String humanRankLabel(int rank) =>
      rank > 0 ? '${rank}k' : '${1 - rank}d';

  String get resolvedHumanSLProfile => humanSLProfile?.trim().isNotEmpty == true
      ? humanSLProfile!.trim()
      : 'rank_${humanRankLabel(resolvedHumanStyleRank)}';

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
    if (!useBuiltinHumanStyle && humanModelId == null) {
      throw ArgumentError('人类棋风需要选择独立 human model 或人类棋风主模型');
    }
    if (useBuiltinHumanStyle && humanModelId != null) {
      throw ArgumentError('使用人类棋风主模型时不能再叠加独立 human model');
    }
  }
}
