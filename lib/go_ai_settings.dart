import 'dart:math';

import 'game_session.dart';

enum GoOpponentMode { kataGo, basic, local }

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

enum GoAiStyle { modern, traditional }

extension GoAiStyleX on GoAiStyle {
  String get label => switch (this) {
    GoAiStyle.modern => '现代',
    GoAiStyle.traditional => '传统',
  };
}

class GoAiSettings {
  final GoOpponentMode opponentMode;
  final GoPlayerColor playerColor;
  final GoAiRank rank;
  final GoAiStyle style;
  final String modelId;
  final String engineProfileId;

  const GoAiSettings({
    this.opponentMode = GoOpponentMode.kataGo,
    this.playerColor = GoPlayerColor.black,
    this.rank = GoAiRank.intermediate,
    this.style = GoAiStyle.modern,
    this.modelId = 'b6',
    this.engineProfileId = 'default',
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
  }) => GoAiSettings(
    opponentMode: opponentMode ?? this.opponentMode,
    playerColor: playerColor ?? this.playerColor,
    rank: rank ?? this.rank,
    style: style ?? this.style,
    modelId: modelId ?? this.modelId,
    engineProfileId: engineProfileId ?? this.engineProfileId,
  );

  Map<String, Object> toJson() => {
    'opponentMode': opponentMode.name,
    'playerColor': playerColor.name,
    'rank': rank.name,
    'style': style.name,
    'modelId': modelId,
    'engineProfileId': engineProfileId,
  };

  factory GoAiSettings.fromJson(Map<String, Object?> json) => GoAiSettings(
    opponentMode: GoOpponentMode.values.firstWhere(
      (value) => value.name == json['opponentMode'],
      orElse: () => GoOpponentMode.kataGo,
    ),
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
  );
}
