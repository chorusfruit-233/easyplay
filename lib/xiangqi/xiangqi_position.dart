import '../game_session.dart' show Cell;
import 'xiangqi_piece.dart';
import 'xiangqi_side.dart';

/// Immutable 10×9 board; row zero is Black's home rank. Piece identities are
/// preserved by movement, but excluded from the repetition position key.
class XiangqiPosition {
  XiangqiPosition({
    required List<List<XiangqiPiece?>> board,
    this.sideToMove = XiangqiSide.red,
    this.halfmoveClock = 0,
    this.fullmoveNumber = 1,
  }) : board = _validated(board, halfmoveClock, fullmoveNumber);
  final List<List<XiangqiPiece?>> board;
  final XiangqiSide sideToMove;
  final int halfmoveClock, fullmoveNumber;
  static List<List<XiangqiPiece?>> _validated(
    List<List<XiangqiPiece?>> board,
    int half,
    int full,
  ) {
    if (board.length != 10 ||
        board.any((row) => row.length != 9) ||
        half < 0 ||
        full < 1) {
      throw const FormatException('无效的中国象棋局面');
    }
    final counts = <(XiangqiSide, XiangqiPieceType), int>{};
    final ids = <int>{};
    final copy = <List<XiangqiPiece?>>[];
    for (var r = 0; r < 10; r++) {
      final row = <XiangqiPiece?>[];
      for (var c = 0; c < 9; c++) {
        final piece = board[r][c];
        if (piece == null) {
          row.add(null);
          continue;
        }
        final side = piece.side, type = piece.type;
        final key = (side, type);
        counts[key] = (counts[key] ?? 0) + 1;
        final id = piece.id < 0 ? r * 9 + c : piece.id;
        if (!ids.add(id)) throw const FormatException('重复棋子标识');
        if (type == XiangqiPieceType.general && !side.inPalace(r, c)) {
          throw const FormatException('将帅必须在九宫');
        }
        if (type == XiangqiPieceType.advisor &&
            (!side.inPalace(r, c) ||
                (r + c) % 2 != (side == XiangqiSide.red ? 0 : 1))) {
          throw const FormatException('仕士位置无效');
        }
        if (type == XiangqiPieceType.elephant) {
          final rank = side == XiangqiSide.red ? 9 - r : r;
          if (!const {
            (0, 2),
            (0, 6),
            (2, 0),
            (2, 4),
            (2, 8),
            (4, 2),
            (4, 6),
          }.contains((rank, c))) {
            throw const FormatException('相象位置无效');
          }
        }
        if (type == XiangqiPieceType.soldier) {
          final rank = side == XiangqiSide.red ? 9 - r : r;
          if (rank < 3 || rank < 5 && c.isOdd) {
            throw const FormatException('兵卒位置无效');
          }
        }
        row.add(XiangqiPiece(side, type, id: id));
      }
      copy.add(List.unmodifiable(row));
    }
    for (final side in XiangqiSide.values) {
      for (final type in XiangqiPieceType.values) {
        final count = counts[(side, type)] ?? 0;
        final maximum = type == XiangqiPieceType.general
            ? 1
            : type == XiangqiPieceType.soldier
            ? 5
            : 2;
        if (count > maximum || type == XiangqiPieceType.general && count != 1) {
          throw const FormatException('中国象棋棋子数量无效');
        }
      }
    }
    return List.unmodifiable(copy);
  }

  factory XiangqiPosition.initial() {
    const order = [
      XiangqiPieceType.chariot,
      XiangqiPieceType.horse,
      XiangqiPieceType.elephant,
      XiangqiPieceType.advisor,
      XiangqiPieceType.general,
      XiangqiPieceType.advisor,
      XiangqiPieceType.elephant,
      XiangqiPieceType.horse,
      XiangqiPieceType.chariot,
    ];
    return XiangqiPosition(
      board: List.generate(
        10,
        (r) => List.generate(9, (c) {
          final side = r < 5 ? XiangqiSide.black : XiangqiSide.red;
          if (r == 0 || r == 9) return XiangqiPiece(side, order[c]);
          if ((r == 2 || r == 7) && (c == 1 || c == 7)) {
            return XiangqiPiece(side, XiangqiPieceType.cannon);
          }
          if ((r == 3 || r == 6) && c.isEven) {
            return XiangqiPiece(side, XiangqiPieceType.soldier);
          }
          return null;
        }),
      ),
    );
  }
  bool inside(Cell cell) =>
      cell.row >= 0 && cell.row < 10 && cell.col >= 0 && cell.col < 9;
  XiangqiPiece? pieceAt(Cell cell) =>
      inside(cell) ? board[cell.row][cell.col] : null;
  XiangqiPosition withTurn(XiangqiSide side) => XiangqiPosition(
    board: board,
    sideToMove: side,
    halfmoveClock: halfmoveClock,
    fullmoveNumber: fullmoveNumber,
  );
}
