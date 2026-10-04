import 'xiangqi_side.dart';

enum XiangqiPieceType {
  general,
  advisor,
  elephant,
  horse,
  chariot,
  cannon,
  soldier,
}

class XiangqiPiece {
  const XiangqiPiece(this.side, this.type, {this.id = -1});
  final XiangqiSide side;
  final XiangqiPieceType type;

  /// Stable identity follows a piece through moves, including repeated boards.
  final int id;
  String get fen {
    final value = 'kabnrcp'[type.index];
    return side == XiangqiSide.red ? value.toUpperCase() : value;
  }

  String get label => (side == XiangqiSide.red
      ? const ['帅', '仕', '相', '马', '车', '炮', '兵']
      : const ['将', '士', '象', '马', '车', '炮', '卒'])[type.index];
}
