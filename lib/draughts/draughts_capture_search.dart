import '../game_session.dart' show Cell, Side;
import 'draughts_move.dart';
import 'draughts_piece.dart';
import 'draughts_position.dart';
import 'draughts_rules.dart';

class CaptureSearchState {
  CaptureSearchState(this.position, this.captured, this.currentRank);
  final DraughtsPosition position;
  final Set<Cell> captured;
  final DraughtsRank currentRank;
}

class DraughtsCaptureSearch {
  const DraughtsCaptureSearch(this.rules);
  final DraughtsRules rules;

  List<DraughtsMove> search(DraughtsPosition position, Side side) {
    final results = <DraughtsMove>[];
    for (var r = 0; r < rules.boardSize; r++) {
      for (var c = 0; c < rules.boardSize; c++) {
        final start = Cell(r, c);
        final piece = position[start];
        if (piece?.side != side) continue;
        _walk(
          position,
          side,
          start,
          start,
          piece!.rank,
          <Cell>[],
          <Cell>[],
          {},
          null,
          results,
        );
      }
    }
    return results;
  }

  void _walk(
    DraughtsPosition board,
    Side side,
    Cell start,
    Cell current,
    DraughtsRank rank,
    List<Cell> path,
    List<Cell> captures,
    Set<Cell> alreadyCaptured,
    (int, int)? lastDirection,
    List<DraughtsMove> out,
  ) {
    final steps = _captureSteps(board, side, current, rank, alreadyCaptured);
    if (rules.forbidCaptureReverse && lastDirection != null) {
      steps.removeWhere(
        (step) => step.dr == -lastDirection.$1 && step.dc == -lastDirection.$2,
      );
    }
    if (steps.isEmpty) {
      if (captures.isNotEmpty) {
        out.add(DraughtsMove(path: [start, ...path], captures: captures));
      }
      return;
    }
    for (final step in steps) {
      final nextCaptured = {...alreadyCaptured, step.captured};
      final nextRank = _rankAfterLanding(rank, side, step.to);
      final nextBoard = _simulate(board, current, step, nextRank);
      final nextPath = [...path, step.to];
      final nextCaptures = [...captures, step.captured];
      final reachedPromotion =
          rank == DraughtsRank.man && rules.isPromotionCell(side, step.to);
      if (reachedPromotion &&
          rules.promotion == PromotionPolicy.stopOnPromotion) {
        out.add(
          DraughtsMove(path: [start, ...nextPath], captures: nextCaptures),
        );
      } else {
        _walk(
          nextBoard,
          side,
          start,
          step.to,
          nextRank,
          nextPath,
          nextCaptures,
          nextCaptured,
          (step.dr, step.dc),
          out,
        );
      }
    }
  }

  DraughtsRank _rankAfterLanding(DraughtsRank rank, Side side, Cell to) =>
      rank == DraughtsRank.man &&
          rules.promotion == PromotionPolicy.promoteAndContinue &&
          rules.isPromotionCell(side, to)
      ? DraughtsRank.king
      : rank;

  DraughtsPosition _simulate(
    DraughtsPosition board,
    Cell from,
    _CaptureStep step,
    DraughtsRank rank,
  ) {
    final moving = board[from]!;
    var result = board
        .copyWithCell(from, null)
        .copyWithCell(step.to, DraughtsPiece(moving.side, rank));
    if (rules.captureRemoval == CaptureRemovalPolicy.immediate) {
      result = result.copyWithCell(step.captured, null);
    }
    return result;
  }

  List<_CaptureStep> _captureSteps(
    DraughtsPosition board,
    Side side,
    Cell from,
    DraughtsRank rank,
    Set<Cell> captured,
  ) {
    final piece = board[from];
    if (piece == null) return const [];
    final directions = _directions(side, rank, capture: true);
    final flying =
        rank == DraughtsRank.king && rules.kingCapture != KingCaptureRule.short;
    final result = <_CaptureStep>[];
    for (final (dr, dc) in directions) {
      var r = from.row + dr;
      var c = from.col + dc;
      if (!flying) {
        final victim = Cell(r, c);
        final landing = Cell(r + dr, c + dc);
        final other = board[victim];
        if (board.inside(landing) &&
            rules.isPlayable(landing) &&
            other != null &&
            other.side != side &&
            !captured.contains(victim) &&
            (rank == DraughtsRank.king ||
                rules.menMayCaptureKings ||
                other.rank == DraughtsRank.man) &&
            board[landing] == null &&
            !captured.contains(landing)) {
          result.add(_CaptureStep(victim, landing, dr, dc));
        }
        continue;
      }
      Cell? victim;
      while (board.inside(Cell(r, c)) && rules.isPlayable(Cell(r, c))) {
        final cell = Cell(r, c);
        final occupant = board[cell];
        if (occupant != null) {
          if (captured.contains(cell) ||
              occupant.side == side ||
              victim != null ||
              (rank == DraughtsRank.man &&
                  !rules.menMayCaptureKings &&
                  occupant.rank == DraughtsRank.king)) {
            break;
          }
          victim = cell;
        } else if (victim != null) {
          result.add(_CaptureStep(victim, cell, dr, dc));
        }
        r += dr;
        c += dc;
      }
    }
    return result;
  }

  List<(int, int)> _directions(
    Side side,
    DraughtsRank rank, {
    required bool capture,
  }) {
    if (rank == DraughtsRank.king) {
      if (rules.kingCapture == KingCaptureRule.flyingOrthogonal ||
          rules.geometry == BoardGeometry.orthogonalAllSquares) {
        return const [(1, 0), (-1, 0), (0, 1), (0, -1)];
      }
      return const [(1, 1), (1, -1), (-1, 1), (-1, -1)];
    }
    if (rules.manCapture == ManCaptureRule.orthogonal) {
      final forward = rules.forward(side);
      return [(forward, 0), (0, 1), (0, -1)];
    }
    final forward = rules.forward(side);
    return rules.manCapture == ManCaptureRule.forwardAndBackward
        ? const [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        : [(forward, 1), (forward, -1)];
  }
}

class _CaptureStep {
  const _CaptureStep(this.captured, this.to, this.dr, this.dc);
  final Cell captured;
  final Cell to;
  final int dr;
  final int dc;
}
