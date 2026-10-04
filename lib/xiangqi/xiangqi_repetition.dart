// Asian chase classification adapted from official Pikafish position.cpp,
// commit 4c17cee11f888ae1d48a9494f2e2239f019f0a1f, GPL-3.0-or-later.
import '../game_session.dart' show Cell;
import 'xiangqi_fen.dart';
import 'xiangqi_move.dart';
import 'xiangqi_move_generator.dart';
import 'xiangqi_piece.dart';
import 'xiangqi_position.dart';
import 'xiangqi_side.dart';

class XiangqiMoveRecord {
  XiangqiMoveRecord({
    required this.before,
    required this.after,
    required this.move,
    required this.piece,
    this.captured,
    required this.gaveCheck,
    required Set<int> chasedIds,
  }) : chasedIds = Set.unmodifiable(chasedIds);
  final XiangqiPosition before, after;
  final XiangqiMove move;
  final XiangqiPiece piece;
  final XiangqiPiece? captured;
  final bool gaveCheck;
  final Set<int> chasedIds;
  XiangqiSide get side => piece.side;
}

class XiangqiRepetitionResult {
  const XiangqiRepetitionResult({this.offender, required this.cyclePlies});
  final XiangqiSide? offender;
  final int cyclePlies;
  bool get isDraw => offender == null;
}

class XiangqiRepetition {
  static String positionKey(XiangqiPosition p) =>
      exportXiangqiFen(p).split(' ').take(2).join(' ');

  XiangqiRepetitionResult? evaluate(
    XiangqiPosition position,
    List<XiangqiMoveRecord> history,
  ) {
    if (history.length < 4) return null;
    final current = positionKey(position);
    final positions = [
      history.first.before,
      for (final record in history) record.after,
    ];
    var earliest = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].captured != null) {
        earliest = i + 1;
        break;
      }
    }
    final repeats = <int>[];
    for (var i = history.length - 4; i >= earliest; i -= 2) {
      if (positionKey(positions[i]) == current) repeats.add(i);
      if (repeats.length == 2) break;
    }
    if (repeats.length < 2) return null;
    final period = history.sublist(repeats.last);
    final sideMoves = {
      for (final side in XiangqiSide.values)
        side: period.where((record) => record.side == side).toList(),
    };
    final checkers = [
      for (final side in XiangqiSide.values)
        if (sideMoves[side]!.isNotEmpty &&
            sideMoves[side]!.every((record) => record.gaveCheck))
          side,
    ];
    if (checkers.isNotEmpty) {
      return XiangqiRepetitionResult(
        offender: checkers.length == 1 ? checkers.single : null,
        cyclePlies: period.length,
      );
    }
    // The pinned Asian implementation treats mixed checking/chasing cycles as
    // allowed repetition unless a side checks on every one of its turns.
    if (period.any((record) => record.gaveCheck)) {
      return XiangqiRepetitionResult(cyclePlies: period.length);
    }
    final chasers = <XiangqiSide>[];
    for (final side in XiangqiSide.values) {
      Set<int>? common;
      for (final record in sideMoves[side]!) {
        common = common == null
            ? record.chasedIds.toSet()
            : common.intersection(record.chasedIds);
      }
      if (common != null && common.isNotEmpty) chasers.add(side);
    }
    return XiangqiRepetitionResult(
      offender: chasers.length == 1 ? chasers.single : null,
      cyclePlies: period.length,
    );
  }

  /// Rule chases are newly created legal captures, not every geometric attack.
  /// Kings/pawns may pursue; unadvanced pawns are exempt. A legal recapture or
  /// a symmetric same-type attack exempts a target, except attacks by a weaker
  /// horse/cannon on a rook and advisor/elephant on a major piece.
  static Set<int> chased(XiangqiPosition position, XiangqiSide side) {
    final p = position.withTurn(side), result = <int>{};
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final from = Cell(r, c), piece = p.pieceAt(from);
        if (piece == null ||
            piece.side != side ||
            [
              XiangqiPieceType.general,
              XiangqiPieceType.soldier,
            ].contains(piece.type)) {
          continue;
        }
        for (final move in XiangqiMoveGenerator.legalMoves(p, from: from)) {
          final target = p.pieceAt(move.to);
          if (target == null ||
              target.type == XiangqiPieceType.general ||
              target.type == XiangqiPieceType.soldier &&
                  !target.side.crossedRiver(move.to.row)) {
            continue;
          }
          final weakMajor =
              [
                XiangqiPieceType.horse,
                XiangqiPieceType.cannon,
              ].contains(piece.type) &&
              target.type == XiangqiPieceType.chariot;
          final minorMajor =
              [
                XiangqiPieceType.advisor,
                XiangqiPieceType.elephant,
              ].contains(piece.type) &&
              [
                XiangqiPieceType.horse,
                XiangqiPieceType.chariot,
                XiangqiPieceType.cannon,
                XiangqiPieceType.soldier,
              ].contains(target.type);
          if (weakMajor || minorMajor) {
            result.add(target.id);
            continue;
          }
          final captured = XiangqiMoveGenerator.applyUnchecked(p, move);
          if (XiangqiMoveGenerator.legalMoves(
            captured,
          ).any((reply) => reply.to == move.to)) {
            continue;
          }
          if (piece.type == target.type &&
              XiangqiMoveGenerator.legalMoves(
                p.withTurn(side.opponent),
                from: move.to,
              ).any((reply) => reply.to == from)) {
            continue;
          }
          result.add(target.id);
        }
      }
    }
    return result;
  }
}
