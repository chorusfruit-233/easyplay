import '../game_session.dart' show Cell, Side, SideX;
import 'chess_fen.dart';
import 'chess_move.dart';
import 'chess_move_generator.dart';
import 'chess_piece.dart';
import 'chess_position.dart';
import 'chess_result.dart';
import 'chess_uci.dart';

const chessRulesVersion = 1;

class ChessSnapshot {
  ChessSnapshot(
    this.position,
    this.result,
    this.moveCount,
    Map<String, int> counts, {
    this.claimMove,
  }) : repetitionCounts = Map.unmodifiable(counts);
  final ChessPosition position;
  final ChessResult? result;
  final int moveCount;
  final Map<String, int> repetitionCounts;
  final ChessMove? claimMove;
}

/// The sole rules authority for local, AI, restored and LAN games.
class ChessSession {
  ChessSession({ChessPosition? position})
    : initialPosition = position ?? ChessPosition.initial() {
    _position = initialPosition;
    _repetitions[positionKey(_position)] = 1;
    _adjudicate();
  }
  final ChessPosition initialPosition;
  late ChessPosition _position;
  ChessResult? _result;
  ChessMove? _claimMove;
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
  String get initialFen => exportFen(initialPosition);
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

  void _save() => _undo.add(
    ChessSnapshot(
      position,
      result,
      _moves.length,
      _repetitions,
      claimMove: _claimMove,
    ),
  );

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
    _claimMove = intendedMove;
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
    _claimMove = snapshot.claimMove;
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

  Map<String, Object?> toJson() => {
    'version': 1,
    'game': 'chess',
    'rulesVersion': chessRulesVersion,
    'initialFen': initialFen,
    'moves': moves.map(moveToUci).toList(),
    'result': result == null
        ? null
        : {'reason': result!.reason.name, 'winner': result!.winner?.name},
    if (_claimMove != null) 'claimMove': moveToUci(_claimMove!),
  };

  /// Rebuild rule history and undo through legal play, never trust saved FEN
  /// or repetition counters as a replacement for the complete move sequence.
  factory ChessSession.fromJson(Object? value) {
    Never invalid() => throw const FormatException('无效的国际象棋棋谱');
    if (value is! Map ||
        value['version'] != 1 ||
        value['game'] != 'chess' ||
        value['rulesVersion'] != chessRulesVersion ||
        value['initialFen'] is! String ||
        value['moves'] is! List) {
      invalid();
    }
    final raw = value['moves'] as List;
    if (raw.length > 10000 || raw.any((m) => m is! String)) invalid();
    final session = ChessSession(
      position: parseFen(value['initialFen'] as String),
    );
    for (final move in raw) {
      if (!session.applyMove(parseUciMove(move as String))) invalid();
    }
    final ending = value['result'];
    ChessResult? expected;
    if (ending != null) {
      if (ending is! Map) invalid();
      final reason = ChessEndReason.values
          .where((r) => r.name == ending['reason'])
          .firstOrNull;
      final winner = Side.values
          .where((s) => s.name == ending['winner'])
          .firstOrNull;
      if (reason == null || ending['winner'] != null && winner == null) {
        invalid();
      }
      expected = ChessResult(reason: reason, winner: winner);
    }
    final claim = value['claimMove'];
    if (claim != null &&
        (claim is! String ||
            ![
              ChessEndReason.threefoldRepetition,
              ChessEndReason.fiftyMoveRule,
            ].contains(expected?.reason))) {
      invalid();
    }
    if (!session.gameOver && expected != null) {
      switch (expected.reason) {
        case ChessEndReason.resignation:
          if (expected.winner == null) invalid();
          session.resign(expected.winner!.opponent);
        case ChessEndReason.drawAgreement:
          session.agreeDraw();
        case ChessEndReason.threefoldRepetition || ChessEndReason.fiftyMoveRule:
          session.claimDraw(
            claim == null ? null : parseUciMove(claim as String),
          );
        default:
          break;
      }
    }
    if (session.result != expected) invalid();
    return session;
  }

  void dispose() {
    _moves.clear();
    _undo.clear();
    _repetitions.clear();
  }
}
