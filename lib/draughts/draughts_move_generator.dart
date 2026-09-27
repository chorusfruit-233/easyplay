import '../game_session.dart' show Cell, Side;
import 'draughts_capture_search.dart';
import 'draughts_move.dart';
import 'draughts_piece.dart';
import 'draughts_position.dart';
import 'draughts_rules.dart';

class DraughtsMoveGenerator {
  DraughtsMoveGenerator(this.rules)
    : _captureSearch = DraughtsCaptureSearch(rules);
  final DraughtsRules rules;
  final DraughtsCaptureSearch _captureSearch;

  List<DraughtsMove> legalMoves(DraughtsPosition position, Side side) {
    final captures = _captureSearch.search(position, side);
    if (captures.isNotEmpty) {
      return rules.capturePriority.select(position, captures);
    }
    final moves = <DraughtsMove>[];
    for (var row = 0; row < rules.boardSize; row++) {
      for (var col = 0; col < rules.boardSize; col++) {
        final from = Cell(row, col);
        final piece = position[from];
        if (piece?.side != side) continue;
        for (final to in _quietTargets(position, side, from, piece!.rank)) {
          moves.add(DraughtsMove(path: [from, to]));
        }
      }
    }
    return moves;
  }

  List<Cell> _quietTargets(
    DraughtsPosition board,
    Side side,
    Cell from,
    DraughtsRank rank,
  ) {
    final directions = <(int, int)>[];
    final flying =
        rank == DraughtsRank.king && rules.kingMove != KingMoveRule.short;
    if (rank == DraughtsRank.king) {
      if (rules.kingMove == KingMoveRule.flyingOrthogonal ||
          rules.geometry == BoardGeometry.orthogonalAllSquares) {
        directions.addAll(const [(1, 0), (-1, 0), (0, 1), (0, -1)]);
      } else {
        directions.addAll(const [(1, 1), (1, -1), (-1, 1), (-1, -1)]);
      }
    } else {
      switch (rules.manMove) {
        case ManMoveRule.forwardDiagonal:
          directions.addAll([
            (rules.forward(side), 1),
            (rules.forward(side), -1),
          ]);
        case ManMoveRule.forwardOrthogonalWithSideways:
          directions.addAll([(rules.forward(side), 0), (0, 1), (0, -1)]);
      }
    }
    final targets = <Cell>[];
    for (final (dr, dc) in directions) {
      var r = from.row + dr;
      var c = from.col + dc;
      while (board.inside(Cell(r, c)) &&
          rules.isPlayable(Cell(r, c)) &&
          board[Cell(r, c)] == null) {
        targets.add(Cell(r, c));
        if (!flying) break;
        r += dr;
        c += dc;
      }
    }
    return targets;
  }
}
