import '../game_session.dart' show Cell;
import 'xiangqi_move.dart';
import 'xiangqi_piece.dart';
import 'xiangqi_position.dart';
import 'xiangqi_side.dart';

class XiangqiMoveGenerator {
  static const orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  static bool attacks(XiangqiPosition p, Cell from, Cell to) {
    final piece = p.pieceAt(from);
    if (piece == null || !p.inside(to) || from == to) return false;
    final dr = to.row - from.row, dc = to.col - from.col;
    switch (piece.type) {
      case XiangqiPieceType.general:
        if (dc == 0 &&
            p.pieceAt(to)?.type == XiangqiPieceType.general &&
            _screens(p, from, to) == 0) {
          return true;
        }
        return dr.abs() + dc.abs() == 1 && piece.side.inPalace(to.row, to.col);
      case XiangqiPieceType.advisor:
        return dr.abs() == 1 &&
            dc.abs() == 1 &&
            piece.side.inPalace(to.row, to.col);
      case XiangqiPieceType.elephant:
        return dr.abs() == 2 &&
            dc.abs() == 2 &&
            !piece.side.crossedRiver(to.row) &&
            p.pieceAt(Cell(from.row + dr ~/ 2, from.col + dc ~/ 2)) == null;
      case XiangqiPieceType.horse:
        if (dr.abs() == 2 && dc.abs() == 1) {
          return p.pieceAt(Cell(from.row + dr.sign, from.col)) == null;
        }
        if (dr.abs() == 1 && dc.abs() == 2) {
          return p.pieceAt(Cell(from.row, from.col + dc.sign)) == null;
        }
        return false;
      case XiangqiPieceType.chariot:
        return (dr == 0 || dc == 0) && _screens(p, from, to) == 0;
      case XiangqiPieceType.cannon:
        return (dr == 0 || dc == 0) &&
            _screens(p, from, to) == (p.pieceAt(to) == null ? 0 : 1);
      case XiangqiPieceType.soldier:
        return dc == 0 && dr == piece.side.forward ||
            dr == 0 && dc.abs() == 1 && piece.side.crossedRiver(from.row);
    }
  }

  static int _screens(XiangqiPosition p, Cell from, Cell to) {
    if (from.row != to.row && from.col != to.col) return -1;
    final dr = (to.row - from.row).sign, dc = (to.col - from.col).sign;
    var n = 0;
    for (
      var r = from.row + dr, c = from.col + dc;
      r != to.row || c != to.col;
      r += dr, c += dc
    ) {
      if (p.board[r][c] != null) n++;
    }
    return n;
  }

  static Cell general(XiangqiPosition p, XiangqiSide side) {
    for (var r = 0; r < 10; r++) {
      for (var c = 3; c <= 5; c++) {
        final piece = p.board[r][c];
        if (piece?.side == side && piece?.type == XiangqiPieceType.general) {
          return Cell(r, c);
        }
      }
    }
    throw StateError('缺少将帅');
  }

  static bool isInCheck(XiangqiPosition p, XiangqiSide side) {
    final king = general(p, side);
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        if (p.board[r][c]?.side == side.opponent &&
            attacks(p, Cell(r, c), king)) {
          return true;
        }
      }
    }
    return false;
  }

  static List<XiangqiMove> pseudoLegalMoves(XiangqiPosition p, {Cell? from}) {
    final moves = <XiangqiMove>[];
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final origin = Cell(r, c), piece = p.pieceAt(origin);
        if (piece?.side != p.sideToMove || from != null && from != origin) {
          continue;
        }
        for (var tr = 0; tr < 10; tr++) {
          for (var tc = 0; tc < 9; tc++) {
            final to = Cell(tr, tc), target = p.pieceAt(to);
            if (target?.side == piece!.side ||
                target?.type == XiangqiPieceType.general) {
              continue;
            }
            if (attacks(p, origin, to)) {
              moves.add(XiangqiMove(from: origin, to: to));
            }
          }
        }
      }
    }
    return moves;
  }

  static List<XiangqiMove> legalMoves(XiangqiPosition p, {Cell? from}) => [
    for (final move in pseudoLegalMoves(p, from: from))
      if (!isInCheck(applyUnchecked(p, move), p.sideToMove)) move,
  ];
  static XiangqiPosition applyUnchecked(XiangqiPosition p, XiangqiMove move) {
    final board = p.board.map((row) => row.toList()).toList();
    final piece = board[move.from.row][move.from.col];
    if (piece == null) throw StateError('空起点');
    final captured = board[move.to.row][move.to.col] != null;
    board[move.to.row][move.to.col] = piece;
    board[move.from.row][move.from.col] = null;
    return XiangqiPosition(
      board: board,
      sideToMove: p.sideToMove.opponent,
      halfmoveClock: captured ? 0 : p.halfmoveClock + 1,
      fullmoveNumber:
          p.fullmoveNumber + (p.sideToMove == XiangqiSide.black ? 1 : 0),
    );
  }
}

int xiangqiPerft(XiangqiPosition p, int depth) {
  if (depth < 0) throw ArgumentError.value(depth, 'depth');
  if (depth == 0) return 1;
  var n = 0;
  for (final move in XiangqiMoveGenerator.legalMoves(p)) {
    n += xiangqiPerft(XiangqiMoveGenerator.applyUnchecked(p, move), depth - 1);
  }
  return n;
}
