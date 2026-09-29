import '../game_session.dart' show Cell, Side, SideX;
import 'chess_move.dart';
import 'chess_piece.dart';
import 'chess_position.dart';

class ChessMoveGenerator {
  static const _knights = [
    (2, 1),
    (2, -1),
    (-2, 1),
    (-2, -1),
    (1, 2),
    (1, -2),
    (-1, 2),
    (-1, -2),
  ];
  static const _rays = [
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (1, 1),
    (1, -1),
    (-1, 1),
    (-1, -1),
  ];

  static bool isAttacked(ChessPosition p, Cell target, Side by) {
    final pawnRow = target.row + (by == Side.white ? 1 : -1);
    for (final dc in [-1, 1]) {
      final piece = p.pieceAt(Cell(pawnRow, target.col + dc));
      if (piece?.side == by && piece?.type == ChessPieceType.pawn) return true;
    }
    for (final d in _knights) {
      final piece = p.pieceAt(Cell(target.row + d.$1, target.col + d.$2));
      if (piece?.side == by && piece?.type == ChessPieceType.knight) {
        return true;
      }
    }
    for (var i = 0; i < _rays.length; i++) {
      final d = _rays[i];
      var r = target.row + d.$1, c = target.col + d.$2, distance = 1;
      while (ChessPosition.inside(Cell(r, c))) {
        final piece = p.board[r][c];
        if (piece != null) {
          if (piece.side == by &&
              (piece.type == ChessPieceType.queen ||
                  (distance == 1 && piece.type == ChessPieceType.king) ||
                  (i < 4 && piece.type == ChessPieceType.rook) ||
                  (i >= 4 && piece.type == ChessPieceType.bishop))) {
            return true;
          }
          break;
        }
        r += d.$1;
        c += d.$2;
        distance++;
      }
    }
    return false;
  }

  static Cell? kingSquare(ChessPosition p, Side side) {
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final piece = p.board[r][c];
        if (piece?.side == side && piece?.type == ChessPieceType.king) {
          return Cell(r, c);
        }
      }
    }
    return null;
  }

  static bool isInCheck(ChessPosition p, Side side) {
    final king = kingSquare(p, side);
    return king == null || isAttacked(p, king, side.opponent);
  }

  static List<ChessMove> legalMoves(ChessPosition p, {Cell? from}) {
    final result = <ChessMove>[];
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final cell = Cell(r, c);
        if (from != null && from != cell) continue;
        final piece = p.board[r][c];
        if (piece == null || piece.side != p.sideToMove) continue;
        for (final move in _pseudoMoves(p, cell, piece)) {
          if (!isInCheck(applyUnchecked(p, move), piece.side)) result.add(move);
        }
      }
    }
    return result;
  }

  static Iterable<ChessMove> _pseudoMoves(
    ChessPosition p,
    Cell from,
    ChessPiece piece,
  ) sync* {
    bool available(Cell to) =>
        ChessPosition.inside(to) &&
        p.pieceAt(to)?.side != piece.side &&
        p.pieceAt(to)?.type != ChessPieceType.king;
    Iterable<ChessMove> pawnMoves(Cell to) sync* {
      if (to.row == 0 || to.row == 7) {
        for (final type in [
          ChessPieceType.queen,
          ChessPieceType.rook,
          ChessPieceType.bishop,
          ChessPieceType.knight,
        ]) {
          yield ChessMove(from: from, to: to, promotion: type);
        }
      } else {
        yield ChessMove(from: from, to: to);
      }
    }

    switch (piece.type) {
      case ChessPieceType.pawn:
        final dir = piece.side == Side.white ? -1 : 1;
        final one = Cell(from.row + dir, from.col);
        if (ChessPosition.inside(one) && p.pieceAt(one) == null) {
          yield* pawnMoves(one);
          final two = Cell(from.row + 2 * dir, from.col);
          if (from.row == (piece.side == Side.white ? 6 : 1) &&
              p.pieceAt(two) == null) {
            yield ChessMove(from: from, to: two);
          }
        }
        for (final dc in [-1, 1]) {
          final to = Cell(from.row + dir, from.col + dc);
          if (!available(to)) continue;
          final captured = p.pieceAt(Cell(from.row, to.col));
          if (p.pieceAt(to) != null ||
              (to == p.enPassantTarget &&
                  captured?.side == piece.side.opponent &&
                  captured?.type == ChessPieceType.pawn)) {
            yield* pawnMoves(to);
          }
        }
      case ChessPieceType.knight:
        for (final d in _knights) {
          final to = Cell(from.row + d.$1, from.col + d.$2);
          if (available(to)) yield ChessMove(from: from, to: to);
        }
      case ChessPieceType.king:
        for (final d in _rays) {
          final to = Cell(from.row + d.$1, from.col + d.$2);
          if (available(to)) yield ChessMove(from: from, to: to);
        }
        final row = piece.side == Side.white ? 7 : 0;
        if (from != Cell(row, 4) || isInCheck(p, piece.side)) return;
        for (final kingSide in [true, false]) {
          if (!p.castlingRights.allows(piece.side, kingSide)) continue;
          final rook = p.pieceAt(Cell(row, kingSide ? 7 : 0));
          if (rook?.side != piece.side || rook?.type != ChessPieceType.rook) {
            continue;
          }
          if ((kingSide ? [5, 6] : [1, 2, 3]).any(
            (c) => p.board[row][c] != null,
          )) {
            continue;
          }
          if ((kingSide ? [5, 6] : [3, 2]).any(
            (c) => isAttacked(p, Cell(row, c), piece.side.opponent),
          )) {
            continue;
          }
          yield ChessMove(from: from, to: Cell(row, kingSide ? 6 : 2));
        }
      case ChessPieceType.bishop:
      case ChessPieceType.rook:
      case ChessPieceType.queen:
        for (var i = 0; i < _rays.length; i++) {
          if (piece.type == ChessPieceType.bishop && i < 4 ||
              piece.type == ChessPieceType.rook && i >= 4) {
            continue;
          }
          final d = _rays[i];
          var r = from.row + d.$1, c = from.col + d.$2;
          while (available(Cell(r, c))) {
            yield ChessMove(from: from, to: Cell(r, c));
            if (p.board[r][c] != null) break;
            r += d.$1;
            c += d.$2;
          }
        }
    }
  }

  /// Only the generator and validated session moves may call this.
  static ChessPosition applyUnchecked(ChessPosition p, ChessMove move) {
    final board = p.board.map((row) => row.toList()).toList();
    final piece = p.pieceAt(move.from)!;
    var captured = p.pieceAt(move.to) != null;
    var rights = p.castlingRights;
    void removeRookRight(Cell cell) {
      for (final side in Side.values) {
        final row = side == Side.white ? 7 : 0;
        if (cell == Cell(row, 0)) rights = rights.without(side, king: false);
        if (cell == Cell(row, 7)) rights = rights.without(side, queen: false);
      }
    }

    if (piece.type == ChessPieceType.king) rights = rights.without(piece.side);
    if (piece.type == ChessPieceType.rook) removeRookRight(move.from);
    if (p.pieceAt(move.to)?.type == ChessPieceType.rook) {
      removeRookRight(move.to);
    }
    board[move.from.row][move.from.col] = null;
    if (piece.type == ChessPieceType.pawn &&
        move.to == p.enPassantTarget &&
        move.from.col != move.to.col &&
        !captured) {
      board[move.from.row][move.to.col] = null;
      captured = true;
    }
    board[move.to.row][move.to.col] = move.promotion == null
        ? piece
        : ChessPiece(piece.side, move.promotion!);
    if (piece.type == ChessPieceType.king &&
        (move.to.col - move.from.col).abs() == 2) {
      final rookCol = move.to.col == 6 ? 7 : 0,
          rookTo = move.to.col == 6 ? 5 : 3;
      board[move.to.row][rookTo] = board[move.to.row][rookCol];
      board[move.to.row][rookCol] = null;
    }
    return ChessPosition(
      board: board,
      sideToMove: p.sideToMove.opponent,
      castlingRights: rights,
      enPassantTarget:
          piece.type == ChessPieceType.pawn &&
              (move.to.row - move.from.row).abs() == 2
          ? Cell((move.from.row + move.to.row) ~/ 2, move.from.col)
          : null,
      halfmoveClock: piece.type == ChessPieceType.pawn || captured
          ? 0
          : p.halfmoveClock + 1,
      fullmoveNumber: p.fullmoveNumber + (p.sideToMove == Side.black ? 1 : 0),
    );
  }
}

int perft(ChessPosition position, int depth) {
  if (depth < 0) throw ArgumentError.value(depth, 'depth');
  if (depth == 0) return 1;
  final moves = ChessMoveGenerator.legalMoves(position);
  if (depth == 1) return moves.length;
  return moves.fold(
    0,
    (n, move) =>
        n + perft(ChessMoveGenerator.applyUnchecked(position, move), depth - 1),
  );
}
