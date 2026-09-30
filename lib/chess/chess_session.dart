import '../game_session.dart' show Cell, Side, SideX;
import 'chess_fen.dart';
import 'chess_move.dart';
import 'chess_move_generator.dart';
import 'chess_piece.dart';
import 'chess_position.dart';
import 'chess_result.dart';

const chessRulesVersion = 1;

class ChessSnapshot {
  ChessSnapshot(
    this.position,
    this.result,
    this.moveCount,
    Map<String, int> counts,
  ) : repetitionCounts = Map.unmodifiable(counts);
  final ChessPosition position;
  final ChessResult? result;
  final int moveCount;
  final Map<String, int> repetitionCounts;
}

/// The sole rules authority for local, AI and LAN games. No persistent storage.
class ChessSession {
  ChessSession({ChessPosition? position})
    : _position = position ?? ChessPosition.initial() {
    _repetitions[positionKey(_position)] = 1;
    _adjudicate();
  }
  ChessPosition _position;
  ChessResult? _result;
  final _moves = <ChessMove>[];
  final _undo = <ChessSnapshot>[];
  final _repetitions = <String, int>{};
  ChessPosition get position => _position;
  ChessResult? get result => _result;
  List<ChessMove> get moves => List.unmodifiable(_moves);
  Side get turn => position.sideToMove;
  bool get gameOver => result != null;
  bool get canUndo => _undo.isNotEmpty;
  String get fen => exportFen(position);
  String get status =>
      result?.label ?? '${turn.label}回合${isInCheck(turn) ? ' · 将军' : ''}';
  bool isInCheck(Side side) => ChessMoveGenerator.isInCheck(position, side);
  List<ChessMove> legalMoves() =>
      gameOver ? [] : ChessMoveGenerator.legalMoves(position);
  List<ChessMove> legalMovesFrom(Cell from) =>
      gameOver ? [] : ChessMoveGenerator.legalMoves(position, from: from);
  bool isLegalMove(ChessMove move) => legalMovesFrom(move.from).contains(move);
  int get repetitionCount => _repetitions[positionKey(position)] ?? 0;

  static String positionKey(ChessPosition p) {
    final fields = exportFen(p).split(' ');
    // An en-passant target matters only when an actual legal capture exists,
    // including the discovered-check restriction on pinned pawns.
    if (p.enPassantTarget != null &&
        !ChessMoveGenerator.legalMoves(p).any(
          (m) =>
              m.to == p.enPassantTarget &&
              m.from.col != m.to.col &&
              p.pieceAt(m.from)?.type == ChessPieceType.pawn,
        )) {
      fields[3] = '-';
    }
    return fields.take(4).join(' ');
  }

  void _save() =>
      _undo.add(ChessSnapshot(position, result, _moves.length, _repetitions));

  bool applyMove(ChessMove move) {
    if (!isLegalMove(move)) return false;
    _save();
    _position = ChessMoveGenerator.applyUnchecked(position, move);
    _moves.add(move);
    final key = positionKey(position);
    _repetitions[key] = (_repetitions[key] ?? 0) + 1;
    _adjudicate();
    return true;
  }

  /// Claims may concern the current position or a declared legal next move.
  ChessEndReason? claimableDraw([ChessMove? intendedMove]) {
    if (gameOver || intendedMove != null && !isLegalMove(intendedMove)) {
      return null;
    }
    final candidate = intendedMove == null
        ? position
        : ChessMoveGenerator.applyUnchecked(position, intendedMove);
    final count =
        (_repetitions[positionKey(candidate)] ?? 0) +
        (intendedMove == null ? 0 : 1);
    if (count >= 3) return ChessEndReason.threefoldRepetition;
    if (candidate.halfmoveClock >= 100) return ChessEndReason.fiftyMoveRule;
    return null;
  }

  bool claimDraw([ChessMove? intendedMove]) {
    final reason = claimableDraw(intendedMove);
    if (reason == null) return false;
    _save();
    _result = ChessResult(reason: reason);
    return true;
  }

  bool resign(Side side) {
    if (gameOver) return false;
    _save();
    _result = ChessResult(
      winner: side.opponent,
      reason: ChessEndReason.resignation,
    );
    return true;
  }

  bool agreeDraw() {
    if (gameOver) return false;
    _save();
    _result = const ChessResult(reason: ChessEndReason.drawAgreement);
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    final snapshot = _undo.removeLast();
    _position = snapshot.position;
    _result = snapshot.result;
    _moves.length = snapshot.moveCount;
    _repetitions
      ..clear()
      ..addAll(snapshot.repetitionCounts);
    return true;
  }

  bool get isDeadPosition {
    final material = <(Cell, ChessPiece)>[];
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final piece = position.board[r][c];
        if (piece != null && piece.type != ChessPieceType.king) {
          material.add((Cell(r, c), piece));
        }
      }
    }
    if (material.isEmpty) return true;
    if (material.length == 1) {
      return [
        ChessPieceType.bishop,
        ChessPieceType.knight,
      ].contains(material.single.$2.type);
    }
    // All bishops on the same colour complex cannot produce mate. Two knights,
    // opposite-coloured bishops and bishop+knight must NOT be auto-drawn.
    return material.every((p) => p.$2.type == ChessPieceType.bishop) &&
        material.map((p) => (p.$1.row + p.$1.col) % 2).toSet().length == 1;
  }

  void _adjudicate() {
    final legal = ChessMoveGenerator.legalMoves(position);
    if (legal.isEmpty) {
      _result = isInCheck(turn)
          ? ChessResult(winner: turn.opponent, reason: ChessEndReason.checkmate)
          : const ChessResult(reason: ChessEndReason.stalemate);
    } else if (isDeadPosition) {
      _result = const ChessResult(reason: ChessEndReason.deadPosition);
    } else if (position.halfmoveClock >= 150) {
      _result = const ChessResult(reason: ChessEndReason.seventyFiveMoveRule);
    } else if (repetitionCount >= 5) {
      _result = const ChessResult(reason: ChessEndReason.fivefoldRepetition);
    }
  }

  void dispose() {
    _moves.clear();
    _undo.clear();
    _repetitions.clear();
  }
}
