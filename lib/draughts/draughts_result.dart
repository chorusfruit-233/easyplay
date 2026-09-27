import '../game_session.dart' show Side;

enum DraughtsEndReason {
  noPieces,
  noMoves,
  resignation,
  drawRule,
  drawAgreement,
}

class DraughtsResult {
  const DraughtsResult({this.winner, required this.reason});
  final Side? winner;
  final DraughtsEndReason reason;
  bool get isDraw => winner == null;
  Map<String, Object?> toJson() => {
    'winner': winner?.name,
    'reason': reason.name,
  };
  factory DraughtsResult.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('invalid result');
    final winnerRaw = value['winner'];
    final winner = winnerRaw == null
        ? null
        : Side.values.where((s) => s.name == winnerRaw).firstOrNull;
    final reason = DraughtsEndReason.values
        .where((r) => r.name == value['reason'])
        .firstOrNull;
    if ((winnerRaw != null && winner == null) || reason == null) {
      throw const FormatException('invalid result');
    }
    return DraughtsResult(winner: winner, reason: reason);
  }
}
