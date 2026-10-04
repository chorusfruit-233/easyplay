enum GomokuVariant {
  freestyle('自由五子棋', '双方连续五子或更多获胜，无禁手'),
  standard('标准五子棋', '双方恰好连续五子获胜，长连不获胜'),
  renju('连珠禁手', '黑方恰好五子获胜，禁长连、双四及双活三；白方五子或更多获胜');

  const GomokuVariant(this.label, this.description);
  final String label;
  final String description;

  static GomokuVariant fromName(Object? name) => switch (name) {
    'freestyle' => freestyle,
    'standard' => standard,
    'renju' => renju,
    _ => throw const FormatException('无效的五子棋规则'),
  };
}
