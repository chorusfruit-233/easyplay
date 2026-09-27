import '../game_session.dart' show Cell, Side;
import 'draughts_piece.dart';
import 'draughts_rules.dart';

class DraughtsPosition {
  DraughtsPosition(this.size, List<DraughtsPiece?> pieces)
    : _pieces = List.unmodifiable(pieces) {
    if (size < 8 || _pieces.length != size * size) {
      throw ArgumentError('position dimensions do not match');
    }
  }

  final int size;
  final List<DraughtsPiece?> _pieces;
  DraughtsPiece? operator [](Cell cell) =>
      inside(cell) ? _pieces[cell.row * size + cell.col] : null;
  bool inside(Cell c) =>
      c.row >= 0 && c.col >= 0 && c.row < size && c.col < size;
  List<DraughtsPiece?> get pieces => _pieces;
  int count(Side side) => _pieces.where((p) => p?.side == side).length;
  String signature(Side turn) =>
      '${turn.name}:${_pieces.map((p) => p == null ? '.' : '${p.side == Side.black ? 'b' : 'w'}${p.rank == DraughtsRank.king ? 'K' : 'm'}').join()}';
  DraughtsPosition copyWithCell(Cell c, DraughtsPiece? piece) {
    final copy = List<DraughtsPiece?>.of(_pieces);
    copy[c.row * size + c.col] = piece;
    return DraughtsPosition(size, copy);
  }

  static DraughtsPosition initial(DraughtsRules rules) {
    final cells = List<DraughtsPiece?>.filled(
      rules.boardSize * rules.boardSize,
      null,
    );
    for (var row = 0; row < rules.boardSize; row++) {
      for (var col = 0; col < rules.boardSize; col++) {
        final cell = Cell(row, col);
        if (!rules.isPlayable(cell)) continue;
        if (row >= rules.startingOffset &&
            row < rules.startingOffset + rules.startingRows) {
          cells[row * rules.boardSize + col] = const DraughtsPiece(Side.black);
        } else if (row >=
                rules.boardSize - rules.startingOffset - rules.startingRows &&
            row < rules.boardSize - rules.startingOffset) {
          cells[row * rules.boardSize + col] = const DraughtsPiece(Side.white);
        }
      }
    }
    return DraughtsPosition(rules.boardSize, cells);
  }

  Map<String, Object?> toJson() => {
    'size': size,
    'pieces': _pieces.map((p) => p?.toJson()).toList(),
  };
  factory DraughtsPosition.fromJson(Object? json) {
    if (json is! Map || json['size'] is! int || json['pieces'] is! List) {
      throw const FormatException('invalid draughts position');
    }
    return DraughtsPosition(
      json['size'] as int,
      (json['pieces'] as List)
          .map((p) => p == null ? null : DraughtsPiece.fromJson(p))
          .toList(),
    );
  }
}
