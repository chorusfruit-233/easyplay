import '../game_session.dart' show Cell;
import 'chess_move.dart';
import 'chess_piece.dart';

String chessSquare(Cell cell) {
  if (cell.row < 0 || cell.row > 7 || cell.col < 0 || cell.col > 7) {
    throw const FormatException('无效的国际象棋坐标');
  }
  return '${String.fromCharCode(97 + cell.col)}${8 - cell.row}';
}

Cell parseChessSquare(String text) {
  if (!RegExp(r'^[a-h][1-8]$').hasMatch(text)) {
    throw const FormatException('无效的国际象棋坐标');
  }
  return Cell(8 - int.parse(text[1]), text.codeUnitAt(0) - 97);
}

String moveToUci(ChessMove move) =>
    '${chessSquare(move.from)}${chessSquare(move.to)}'
    '${move.promotion == null ? '' : 'pnbrqk'[move.promotion!.index]}';

ChessMove parseUciMove(String text) {
  if (!RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(text)) {
    throw const FormatException('无效的 UCI 着法');
  }
  return ChessMove(
    from: parseChessSquare(text.substring(0, 2)),
    to: parseChessSquare(text.substring(2, 4)),
    promotion: text.length == 5
        ? ChessPieceType.values['pnbrqk'.indexOf(text[4])]
        : null,
  );
}
