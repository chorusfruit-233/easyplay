import '../game_session.dart' show Cell;

class XiangqiMove {
  const XiangqiMove({required this.from, required this.to});
  final Cell from, to;
  @override
  bool operator ==(Object other) =>
      other is XiangqiMove && from == other.from && to == other.to;
  @override
  int get hashCode => Object.hash(from, to);
}
