import '../game_session.dart' show Side, SideX;

enum ChessEndReason {
  checkmate,
  stalemate,
  resignation,
  drawAgreement,
  threefoldRepetition,
  fivefoldRepetition,
  fiftyMoveRule,
  seventyFiveMoveRule,
  deadPosition,
}

class ChessResult {
  const ChessResult({this.winner, required this.reason});
  final Side? winner;
  final ChessEndReason reason;
  String get label => switch (reason) {
    ChessEndReason.checkmate => '${winner!.label}将死获胜',
    ChessEndReason.resignation =>
      '${winner!.opponent.label}认输，${winner!.label}获胜',
    ChessEndReason.stalemate => '和棋 · 逼和',
    ChessEndReason.drawAgreement => '和棋 · 双方同意',
    ChessEndReason.threefoldRepetition => '和棋 · 三次重复',
    ChessEndReason.fivefoldRepetition => '和棋 · 五次重复',
    ChessEndReason.fiftyMoveRule => '和棋 · 50 回合规则',
    ChessEndReason.seventyFiveMoveRule => '和棋 · 75 回合规则',
    ChessEndReason.deadPosition => '和棋 · 无法将死',
  };
  @override
  bool operator ==(Object other) =>
      other is ChessResult && winner == other.winner && reason == other.reason;
  @override
  int get hashCode => Object.hash(winner, reason);
}
