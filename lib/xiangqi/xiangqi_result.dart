import 'xiangqi_side.dart';

enum XiangqiEndReason {
  checkmate,
  noLegalMove,
  resignation,
  drawAgreement,
  repetitionViolation,
  repetitionDraw,
  moveLimitDraw,
}

class XiangqiResult {
  const XiangqiResult({this.winner, required this.reason});
  final XiangqiSide? winner;
  final XiangqiEndReason reason;
  String get label => switch (reason) {
    XiangqiEndReason.checkmate => '${winner!.label}将死获胜',
    XiangqiEndReason.noLegalMove => '${winner!.label}困毙获胜',
    XiangqiEndReason.resignation =>
      '${winner!.opponent.label}认输，${winner!.label}获胜',
    XiangqiEndReason.drawAgreement => '和棋 · 双方同意',
    XiangqiEndReason.repetitionViolation =>
      '${winner!.opponent.label}长将或长捉违例，${winner!.label}获胜',
    XiangqiEndReason.repetitionDraw => '和棋 · 允许重复',
    XiangqiEndReason.moveLimitDraw => '和棋 · 60 回合无吃子',
  };
  @override
  bool operator ==(Object other) =>
      other is XiangqiResult &&
      winner == other.winner &&
      reason == other.reason;
  @override
  int get hashCode => Object.hash(winner, reason);
}
