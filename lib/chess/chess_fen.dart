import '../game_session.dart' show Side;
import 'chess_piece.dart';
import 'chess_position.dart';
import 'chess_uci.dart';

String exportFen(ChessPosition position) {
  final rows = <String>[];
  for (final row in position.board) {
    var empty = 0;
    var text = '';
    for (final piece in row) {
      if (piece == null) {
        empty++;
      } else {
        if (empty > 0) text += '$empty';
        empty = 0;
        text += piece.fen;
      }
    }
    if (empty > 0) text += '$empty';
    rows.add(text);
  }
  return '${rows.join('/')} ${position.sideToMove == Side.white ? 'w' : 'b'} '
      '${position.castlingRights.fen} '
      '${position.enPassantTarget == null ? '-' : chessSquare(position.enPassantTarget!)} '
      '${position.halfmoveClock} ${position.fullmoveNumber}';
}

ChessPosition parseFen(String fen) {
  Never invalid() => throw const FormatException('无效的 FEN');
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length != 6 || !['w', 'b'].contains(parts[1])) invalid();
  final rows = parts[0].split('/');
  if (rows.length != 8) invalid();
  final board = <List<ChessPiece?>>[];
  final kings = {Side.white: 0, Side.black: 0};
  for (final row in rows) {
    final cells = <ChessPiece?>[];
    for (final code in row.split('')) {
      final count = int.tryParse(code);
      if (count != null) {
        if (count < 1 || count > 8) invalid();
        cells.addAll(List.filled(count, null));
      } else {
        final index = 'pnbrqk'.indexOf(code.toLowerCase());
        if (index < 0) invalid();
        final side = code == code.toUpperCase() ? Side.white : Side.black;
        if (index == 5) kings[side] = kings[side]! + 1;
        if (index == 0 && (board.isEmpty || board.length == 7)) invalid();
        cells.add(ChessPiece(side, ChessPieceType.values[index]));
      }
    }
    if (cells.length != 8) invalid();
    board.add(cells);
  }
  if (kings.values.any((n) => n != 1)) invalid();
  final rights = parts[2];
  if (rights != '-' &&
      (!RegExp(r'^K?Q?k?q?$').hasMatch(rights) || rights.isEmpty)) {
    invalid();
  }
  final ep = parts[3] == '-' ? null : parseChessSquare(parts[3]);
  if (ep != null &&
      (ep.row != (parts[1] == 'w' ? 2 : 5) || board[ep.row][ep.col] != null)) {
    invalid();
  }
  final half = int.tryParse(parts[4]), full = int.tryParse(parts[5]);
  if (half == null || half < 0 || full == null || full < 1) invalid();
  return ChessPosition(
    board: board,
    sideToMove: parts[1] == 'w' ? Side.white : Side.black,
    castlingRights: ChessCastlingRights(
      whiteKing: rights.contains('K'),
      whiteQueen: rights.contains('Q'),
      blackKing: rights.contains('k'),
      blackQueen: rights.contains('q'),
    ),
    enPassantTarget: ep,
    halfmoveClock: half,
    fullmoveNumber: full,
  );
}
