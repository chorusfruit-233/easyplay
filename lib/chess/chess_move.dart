import '../game_session.dart' show Cell;
import 'chess_piece.dart';

class ChessMove {
  const ChessMove({required this.from, required this.to, this.promotion});
  final Cell from;
  final Cell to;
  final ChessPieceType? promotion;

  @override
  bool operator ==(Object other) =>
      other is ChessMove &&
      from == other.from &&
      to == other.to &&
      promotion == other.promotion;
  @override
  int get hashCode => Object.hash(from, to, promotion);
}
