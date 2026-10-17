import '../game_session.dart' show Cell, Side;

enum GomokuPhase {
  opening,
  exchange,
  fourth,
  declaration,
  secondExchange,
  proposals,
  selection,
  normal,
}

enum GomokuActionType { place, exchange, declare, pass }

class GomokuAction {
  const GomokuAction.place(Cell this.cell)
    : type = GomokuActionType.place,
      count = null,
      exchange = null;
  const GomokuAction.exchange(bool this.exchange)
    : type = GomokuActionType.exchange,
      count = null,
      cell = null;
  const GomokuAction.declare(int this.count)
    : type = GomokuActionType.declare,
      exchange = null,
      cell = null;
  const GomokuAction.pass()
    : type = GomokuActionType.pass,
      count = null,
      cell = null,
      exchange = null;

  final GomokuActionType type;
  final Cell? cell;
  final bool? exchange;
  final int? count;

  Map<String, Object?> toJson() => {
    'type': type.name,
    if (cell != null) 'row': cell!.row,
    if (cell != null) 'col': cell!.col,
    if (exchange != null) 'exchange': exchange,
    if (count != null) 'count': count,
  };

  factory GomokuAction.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('无效的连珠操作');
    if (value['type'] == 'exchange' && value['exchange'] is bool) {
      return GomokuAction.exchange(value['exchange'] as bool);
    }
    if (value['type'] == 'pass') return const GomokuAction.pass();
    if (value['type'] == 'declare' && value['count'] is int) {
      return GomokuAction.declare(value['count'] as int);
    }
    if (value['type'] == 'place' &&
        value['row'] is int &&
        value['col'] is int) {
      return GomokuAction.place(Cell(value['row'] as int, value['col'] as int));
    }
    throw const FormatException('无效的连珠操作');
  }
}

/// A pair is equivalent only if a board symmetry preserves every existing
/// stone's colour and takes one proposal to the other. The fourth stone matters.
bool gomokuEquivalentProposals(List<List<Side?>> board, Cell a, Cell b) {
  Cell transform(Cell cell, int symmetry) {
    var row = cell.row - 7, col = cell.col - 7;
    if (symmetry >= 4) col = -col;
    for (var i = 0; i < symmetry % 4; i++) {
      final next = -col;
      col = row;
      row = next;
    }
    return Cell(row + 7, col + 7);
  }

  for (var symmetry = 0; symmetry < 8; symmetry++) {
    if (transform(a, symmetry) != b) continue;
    var matches = true;
    for (var row = 0; row < 15 && matches; row++) {
      for (var col = 0; col < 15; col++) {
        final target = transform(Cell(row, col), symmetry);
        if (board[row][col] != board[target.row][target.col]) {
          matches = false;
          break;
        }
      }
    }
    if (matches) return true;
  }
  return false;
}
