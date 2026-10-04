import '../xiangqi.dart';

enum XiangqiAiLevel {
  beginner('初学', 0, 150),
  easy('简单', 3, 250),
  normal('普通', 7, 400),
  hard('困难', 12, 700),
  master('大师', 17, 1000),
  maximum('最高', 20, 1500);

  const XiangqiAiLevel(this.label, this.skill, this.movetime);
  final String label;
  final int skill, movetime;
  XiangqiEngineLimits get limits =>
      XiangqiEngineLimits(skill: skill, movetime: movetime);
}

class XiangqiEngineLimits {
  const XiangqiEngineLimits({
    this.skill = 7,
    this.movetime = 400,
    this.initialPosition,
  });
  final int skill, movetime;
  final XiangqiPosition? initialPosition;
}

abstract interface class XiangqiEngine {
  Future<void> start();
  Future<void> newGame();
  Future<XiangqiMove> bestMove(
    XiangqiPosition position,
    List<XiangqiMove> history,
    XiangqiEngineLimits limits,
  );
  Future<void> stop();
  Future<void> dispose();
}

class XiangqiSearchCancelled implements Exception {
  const XiangqiSearchCancelled();
}

abstract interface class PikafishTransport {
  Stream<String> get lines;
  Future<void> start();
  Future<void> send(String command);
  Future<void> close();
}
