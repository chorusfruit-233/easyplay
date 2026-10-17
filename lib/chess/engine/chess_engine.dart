import '../chess.dart';

enum ChessAiLevel {
  beginner('初学', 0, 150, 1320),
  easy('简单', 3, 250, 1730),
  normal('普通', 7, 400, 2520),
  hard('困难', 12, 700, 2910),
  master('大师', 17, 1000, 3140),
  maximum('最高', 20, 1500, null);

  const ChessAiLevel(this.label, this.skill, this.movetime, this.referenceElo);
  final String label;
  final int skill, movetime;

  /// Approximate CCRL Blitz Elo from Stockfish 19's Skill mapping, rounded
  /// to ten points. Full strength has no calibrated Elo; see docs/ENGINE_STRENGTH.md.
  final int? referenceElo;

  String get strengthLabel =>
      referenceElo == null ? '全力（未标定）' : '约 $referenceElo Elo';
  String get displayLabel => '$label · $strengthLabel';

  static const strengthNote =
      '参考 Elo 采用 Stockfish 官方刻度，不代表人类赛事等级分。'
      '实际棋力受设备、平台和思考时间影响；最高档使用全力搜索，Elo 未标定。';

  ChessEngineLimits get limits =>
      ChessEngineLimits(skill: skill, movetime: movetime);
}

class ChessEngineLimits {
  const ChessEngineLimits({this.skill = 7, this.movetime = 400});
  final int skill, movetime;
}

abstract interface class ChessEngine {
  Future<void> start();
  Future<void> newGame();
  Future<ChessMove> bestMove(ChessPosition position, ChessEngineLimits limits);
  Future<void> stop();
  Future<void> dispose();
}

class ChessSearchCancelled implements Exception {
  const ChessSearchCancelled();
}

abstract interface class StockfishTransport {
  Stream<String> get lines;
  Future<void> start();
  Future<void> send(String command);
  Future<void> close();
}
