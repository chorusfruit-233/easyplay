import '../game_session.dart' show Cell, Side;
import 'chess_piece.dart';

class ChessCastlingRights {
  const ChessCastlingRights({
    this.whiteKing = true,
    this.whiteQueen = true,
    this.blackKing = true,
    this.blackQueen = true,
  });
  final bool whiteKing, whiteQueen, blackKing, blackQueen;
  bool allows(Side side, bool kingSide) => side == Side.white
      ? (kingSide ? whiteKing : whiteQueen)
      : (kingSide ? blackKing : blackQueen);
  ChessCastlingRights without(
    Side side, {
    bool king = true,
    bool queen = true,
  }) => ChessCastlingRights(
    whiteKing: whiteKing && !(side == Side.white && king),
    whiteQueen: whiteQueen && !(side == Side.white && queen),
    blackKing: blackKing && !(side == Side.black && king),
    blackQueen: blackQueen && !(side == Side.black && queen),
  );
  String get fen {
    final value =
        '${whiteKing ? 'K' : ''}${whiteQueen ? 'Q' : ''}'
        '${blackKing ? 'k' : ''}${blackQueen ? 'q' : ''}';
    return value.isEmpty ? '-' : value;
  }
}

/// Immutable, complete position. Row zero is rank eight.
class ChessPosition {
  ChessPosition({
    required List<List<ChessPiece?>> board,
    this.sideToMove = Side.white,
    this.castlingRights = const ChessCastlingRights(),
    this.enPassantTarget,
    this.halfmoveClock = 0,
    this.fullmoveNumber = 1,
  }) : board = List.unmodifiable(
         board.map((row) => List<ChessPiece?>.unmodifiable(row)),
       );

  factory ChessPosition.initial() {
    const order = [
      ChessPieceType.rook,
      ChessPieceType.knight,
      ChessPieceType.bishop,
      ChessPieceType.queen,
      ChessPieceType.king,
      ChessPieceType.bishop,
      ChessPieceType.knight,
      ChessPieceType.rook,
    ];
    return ChessPosition(
      board: List.generate(
        8,
        (r) => List.generate(
          8,
          (c) => switch (r) {
            0 => ChessPiece(Side.black, order[c]),
            1 => const ChessPiece(Side.black, ChessPieceType.pawn),
            6 => const ChessPiece(Side.white, ChessPieceType.pawn),
            7 => ChessPiece(Side.white, order[c]),
            _ => null,
          },
        ),
      ),
    );
  }
  final List<List<ChessPiece?>> board;
  final Side sideToMove;
  final ChessCastlingRights castlingRights;
  final Cell? enPassantTarget;
  final int halfmoveClock, fullmoveNumber;
  static bool inside(Cell cell) =>
      cell.row >= 0 && cell.row < 8 && cell.col >= 0 && cell.col < 8;
  ChessPiece? pieceAt(Cell cell) =>
      inside(cell) ? board[cell.row][cell.col] : null;
}
