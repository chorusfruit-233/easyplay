enum GomokuVariant {
  soosyrv8('索索夫-8', '26种指定开局 · 两次交换 · 五手1–8打 · 黑方禁手'),
  professional('竞技连珠', '26种指定开局 · 三手交换 · 五手两打 · 黑方禁手'),
  freestyle('自由五子棋', '双方连续五子或更多获胜，无禁手'),
  standard('标准五子棋', '双方恰好连续五子获胜，长连不获胜'),
  renju('连珠禁手', '黑方恰好五子获胜，禁长连、双四及双活三；白方五子或更多获胜');

  const GomokuVariant(this.label, this.description);
  final String label;
  final String description;

  // The other profiles are retained only to read existing game records.
  static const playable = [soosyrv8];
  bool get competitive => this == professional || this == soosyrv8;
  bool get playableRule => playable.contains(this);
  bool get hasForbiddenMoves => this == renju || competitive;

  static GomokuVariant fromName(Object? name) => switch (name) {
    'soosyrv8' => soosyrv8,
    'professional' => professional,
    'freestyle' => freestyle,
    'standard' => standard,
    'renju' => renju,
    _ => throw const FormatException('无效的五子棋规则'),
  };
}
