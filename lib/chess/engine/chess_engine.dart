import '../chess.dart';

enum ChessAiLevel {
  beginner('初学', 0, 150),
  easy('简单', 3, 250),
  normal('普通', 7, 400),
  hard('困难', 12, 700),
  master('大师', 17, 1000),
  maximum('最高', 20, 1500);

  const ChessAiLevel(this.label, this.skill, this.movetime);
  final String label;
  final int skill, movetime;
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
