import '../game_session.dart' show Side;

enum ChessPieceType { pawn, knight, bishop, rook, queen, king }

class ChessPiece {
  const ChessPiece(this.side, this.type);
  final Side side;
  final ChessPieceType type;
  String get fen {
    final letter = 'pnbrqk'[type.index];
    return side == Side.white ? letter.toUpperCase() : letter;
  }

  String get label => const ['兵', '马', '象', '车', '后', '王'][type.index];
  String get symbol => (side == Side.white ? '♙♘♗♖♕♔' : '♟♞♝♜♛♚')[type.index];
}
