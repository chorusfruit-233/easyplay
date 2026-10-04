import 'xiangqi_piece.dart';
import 'xiangqi_position.dart';
import 'xiangqi_side.dart';
import 'xiangqi_move_generator.dart';

String exportXiangqiFen(XiangqiPosition p) {
  final rows = <String>[];
  for (final row in p.board) {
    var n = 0, text = '';
    for (final piece in row) {
      if (piece == null) {
        n++;
      } else {
        if (n > 0) text += '$n';
        n = 0;
        text += piece.fen;
      }
    }
    if (n > 0) text += '$n';
    rows.add(text);
  }
  return '${rows.join('/')} ${p.sideToMove == XiangqiSide.red ? 'w' : 'b'} - - ${p.halfmoveClock} ${p.fullmoveNumber}';
}

XiangqiPosition parseXiangqiFen(String fen) {
  Never invalid() => throw const FormatException('无效的中国象棋 FEN');
  final fields = fen.trim().split(RegExp(r'\s+'));
  if (fields.length != 6 ||
      !['w', 'b'].contains(fields[1]) ||
      fields[2] != '-' ||
      fields[3] != '-') {
    invalid();
  }
  final rows = fields[0].split('/');
  if (rows.length != 10) invalid();
  final board = <List<XiangqiPiece?>>[];
  for (final row in rows) {
    final cells = <XiangqiPiece?>[];
    for (final code in row.split('')) {
      final n = int.tryParse(code);
      if (n != null) {
        if (n < 1 || n > 9) invalid();
        cells.addAll(List.filled(n, null));
      } else {
        final index = 'kabnrcp'.indexOf(code.toLowerCase());
        if (index < 0) invalid();
        cells.add(
          XiangqiPiece(
            code == code.toUpperCase() ? XiangqiSide.red : XiangqiSide.black,
            XiangqiPieceType.values[index],
          ),
        );
      }
    }
    if (cells.length != 9) invalid();
    board.add(cells);
  }
  final half = int.tryParse(fields[4]), full = int.tryParse(fields[5]);
  if (half == null || full == null) invalid();
  final p = XiangqiPosition(
    board: board,
    sideToMove: fields[1] == 'w' ? XiangqiSide.red : XiangqiSide.black,
    halfmoveClock: half,
    fullmoveNumber: full,
  );
  if (XiangqiMoveGenerator.isInCheck(p, p.sideToMove.opponent)) invalid();
  return p;
}
