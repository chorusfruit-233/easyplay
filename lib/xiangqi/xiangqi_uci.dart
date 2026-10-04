import '../game_session.dart' show Cell;
import 'xiangqi_move.dart';

String xiangqiSquare(Cell cell) {
  if (cell.row < 0 || cell.row > 9 || cell.col < 0 || cell.col > 8) {
    throw const FormatException('无效的中国象棋坐标');
  }
  return '${String.fromCharCode(97 + cell.col)}${9 - cell.row}';
}

Cell parseXiangqiSquare(String text) {
  if (!RegExp(r'^[a-i][0-9]$').hasMatch(text)) {
    throw const FormatException('无效的中国象棋坐标');
  }
  return Cell(9 - int.parse(text[1]), text.codeUnitAt(0) - 97);
}

String xiangqiMoveToUci(XiangqiMove move) =>
    '${xiangqiSquare(move.from)}${xiangqiSquare(move.to)}';
XiangqiMove parseXiangqiUciMove(String text) {
  if (!RegExp(r'^[a-i][0-9][a-i][0-9]$').hasMatch(text)) {
    throw const FormatException('无效的中国象棋 UCI 着法');
  }
  final move = XiangqiMove(
    from: parseXiangqiSquare(text.substring(0, 2)),
    to: parseXiangqiSquare(text.substring(2)),
  );
  if (move.from == move.to) throw const FormatException('起点与终点不能相同');
  return move;
}
