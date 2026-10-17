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

  /// Ordinal app difficulty only; Pikafish has no calibrated Elo mapping.
  int get relativeStrength => index + 1;
  String get strengthLabel =>
      '相对强度 $relativeStrength/${XiangqiAiLevel.values.length}';
  String get displayLabel => '$label · $strengthLabel';

  static const strengthNote =
      '相对强度 1–6 仅表示本应用内的难度顺序，不是 Elo，也不是赛事等级分。'
      '实际棋力受设备和每步思考时间影响。';

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
