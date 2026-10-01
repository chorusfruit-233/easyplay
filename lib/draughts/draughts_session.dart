import '../game_session.dart' show Cell, Side, SideX;
import 'draughts_move.dart';
import 'draughts_move_generator.dart';
import 'draughts_piece.dart';
import 'draughts_position.dart';
import 'draughts_result.dart';
import 'draughts_rules.dart';
import 'draughts_variant.dart';

const draughtsRulesVersion = 1;

class DraughtsSession {
  DraughtsSession(this.rules, {DraughtsPosition? position, Side? turn})
    : position = position ?? DraughtsPosition.initial(rules),
      turn = turn ?? rules.firstMove,
      _generator = DraughtsMoveGenerator(rules) {
    _recordPosition();
    _kingRaceSide = _kingRaceLeader();
    _checkEnd();
  }

  final DraughtsRules rules;
  final DraughtsMoveGenerator _generator;
  DraughtsPosition position;
  Side turn;
  int revision = 0;
  DraughtsResult? result;
  int quietPlies = 0;
  Side? _kingRaceSide;
  int _kingRacePlies = 0;
  final List<DraughtsMove> moves = [];
  final Map<String, int> _repetitions = {};
  final List<_DraughtsSnapshot> _undo = [];
  List<DraughtsMove>? _legalMovesCache;
  int _cacheRevision = -1;

  DraughtsVariant get variant => rules.variant;
  bool get gameOver => result != null;
  int get moveCount => moves.length;
  DraughtsPiece? pieceAt(Cell cell) => position[cell];

  /// Search owns a separate mutable session while retaining all draw history.
  /// The immutable board and rules can be shared; live undo/history are not.
  DraughtsSession fork() {
    final copy = DraughtsSession(rules, position: position, turn: turn);
    copy.quietPlies = quietPlies;
    copy._kingRaceSide = _kingRaceSide;
    copy._kingRacePlies = _kingRacePlies;
    copy._repetitions
      ..clear()
      ..addAll(_repetitions);
    copy.result = result;
    return copy;
  }

  List<DraughtsMove> legalMoves() {
    if (gameOver) return const [];
    if (_cacheRevision == revision && _legalMovesCache != null) {
      return _legalMovesCache!;
    }
    _legalMovesCache = _generator.legalMoves(position, turn);
    _cacheRevision = revision;
    return _legalMovesCache!;
  }

  List<DraughtsMove> legalMovesFrom(Cell cell) =>
      legalMoves().where((move) => move.from == cell).toList(growable: false);

  bool applyMove(DraughtsMove move) {
    if (gameOver) return false;
    final legal = legalMoves()
        .where((candidate) => candidate == move)
        .firstOrNull;
    if (legal == null) return false;
    _save();
    final moving = position[legal.from]!;
    final movingSide = turn;
    final all = List<DraughtsPiece?>.of(position.pieces);
    all[legal.from.row * rules.boardSize + legal.from.col] = null;
    for (final captured in legal.captures) {
      all[captured.row * rules.boardSize + captured.col] = null;
    }
    final touchedPromotion = legal.path.any(
      (cell) => rules.isPromotionCell(moving.side, cell),
    );
    final promote =
        moving.rank == DraughtsRank.man &&
        switch (rules.promotion) {
          PromotionPolicy.afterTurn => rules.isPromotionCell(
            moving.side,
            legal.to,
          ),
          PromotionPolicy.stopOnPromotion ||
          PromotionPolicy.promoteAndContinue => touchedPromotion,
        };
    all[legal.to.row * rules.boardSize + legal.to.col] = promote
        ? moving.promote()
        : moving;
    position = DraughtsPosition(rules.boardSize, all);
    moves.add(legal);
    quietPlies = legal.isCapture || promote || moving.rank == DraughtsRank.man
        ? 0
        : quietPlies + 1;
    turn = turn.opponent;
    revision++;
    _invalidateMoves();
    _updateKingRace(movingSide, legal.isCapture);
    _recordPosition();
    _checkEnd();
    return true;
  }

  bool resign([Side? side]) {
    if (gameOver) return false;
    _save();
    result = DraughtsResult(
      winner: (side ?? turn).opponent,
      reason: DraughtsEndReason.resignation,
    );
    revision++;
    _invalidateMoves();
    return true;
  }

  bool agreeDraw() {
    if (gameOver) return false;
    _save();
    result = const DraughtsResult(reason: DraughtsEndReason.drawAgreement);
    revision++;
    _invalidateMoves();
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    final snapshot = _undo.removeLast();
    position = snapshot.position;
    turn = snapshot.turn;
    result = snapshot.result;
    quietPlies = snapshot.quietPlies;
    _kingRaceSide = snapshot.kingRaceSide;
    _kingRacePlies = snapshot.kingRacePlies;
    moves.removeRange(snapshot.moveCount, moves.length);
    _repetitions
      ..clear()
      ..addAll(snapshot.repetitions);
    revision++;
    _invalidateMoves();
    return true;
  }

  void restore({
    required DraughtsPosition position,
    required Side turn,
    required List<DraughtsMove> history,
    int quietPlies = 0,
    DraughtsResult? result,
    bool keepUndo = false,
  }) {
    if (position.size != rules.boardSize) {
      throw ArgumentError('board size does not match variant');
    }
    this.position = position;
    this.turn = turn;
    this.quietPlies = 0;
    _kingRaceSide = null;
    _kingRacePlies = 0;
    this.result = null;
    moves.clear();
    _undo.clear();
    _repetitions.clear();
    revision++;
    _invalidateMoves();
    _recordPosition();
    for (final move in history) {
      if (!applyMove(move)) {
        throw const FormatException('record contains an illegal move');
      }
    }
    this.quietPlies = quietPlies;
    this.result = result ?? this.result;
    if (!keepUndo) _undo.clear();
  }

  void _save() => _undo.add(
    _DraughtsSnapshot(
      position: position,
      turn: turn,
      result: result,
      quietPlies: quietPlies,
      moveCount: moves.length,
      repetitions: Map.of(_repetitions),
      kingRaceSide: _kingRaceSide,
      kingRacePlies: _kingRacePlies,
    ),
  );

  void _recordPosition() {
    final key = position.signature(turn);
    _repetitions[key] = (_repetitions[key] ?? 0) + 1;
  }

  Side? _kingRaceLeader() {
    if (rules.drawPolicy.kingRaceMoves == null) return null;
    final bySide = <Side, List<DraughtsPiece>>{Side.black: [], Side.white: []};
    for (final piece in position.pieces) {
      if (piece == null) continue;
      bySide[piece.side]!.add(piece);
    }
    bool eligible(Side stronger, Side weaker) {
      final strongPieces = bySide[stronger]!;
      final weakPieces = bySide[weaker]!;
      if (strongPieces.length != 3 ||
          weakPieces.length != 1 ||
          weakPieces.single.rank != DraughtsRank.king ||
          !strongPieces.any((piece) => piece.rank == DraughtsRank.king)) {
        return false;
      }
      return rules.drawPolicy.kingRaceAllowsMen ||
          strongPieces.every((piece) => piece.rank == DraughtsRank.king);
    }

    if (eligible(Side.black, Side.white)) return Side.black;
    if (eligible(Side.white, Side.black)) return Side.white;
    return null;
  }

  void _updateKingRace(Side movingSide, bool capture) {
    final leader = _kingRaceLeader();
    if (leader == null || leader != _kingRaceSide || capture) {
      _kingRaceSide = leader;
      _kingRacePlies = 0;
    } else if (movingSide == leader) {
      _kingRacePlies++;
    }
  }

  void _checkEnd() {
    if (gameOver) return;
    if (position.count(turn) == 0) {
      result = DraughtsResult(
        winner: turn.opponent,
        reason: DraughtsEndReason.noPieces,
      );
      return;
    }
    if (_generator.legalMoves(position, turn).isEmpty) {
      result = DraughtsResult(
        winner: turn.opponent,
        reason: DraughtsEndReason.noMoves,
      );
      return;
    }
    if (quietPlies >= rules.drawPolicy.quietPlies ||
        (_repetitions[position.signature(turn)] ?? 0) >=
            rules.drawPolicy.repetitions ||
        (rules.drawPolicy.kingRaceMoves != null &&
            _kingRacePlies >= rules.drawPolicy.kingRaceMoves!)) {
      result = const DraughtsResult(reason: DraughtsEndReason.drawRule);
    }
  }

  void _invalidateMoves() {
    _legalMovesCache = null;
    _cacheRevision = -1;
  }

  Map<String, Object?> toJson() => {
    'rulesVersion': draughtsRulesVersion,
    'variant': variant.name,
    'position': position.toJson(),
    'turn': turn.name,
    'quietPlies': quietPlies,
    'kingRaceSide': _kingRaceSide?.name,
    'kingRacePlies': _kingRacePlies,
    'moves': moves.map((m) => m.toJson()).toList(),
    'result': result?.toJson(),
  };

  factory DraughtsSession.fromJson(Object? json) {
    if (json is! Map || json['rulesVersion'] != draughtsRulesVersion) {
      throw const FormatException('unsupported draughts rules version');
    }
    final variant = DraughtsVariant.values
        .where((v) => v.name == json['variant'])
        .firstOrNull;
    final turn = Side.values.where((s) => s.name == json['turn']).firstOrNull;
    if (variant == null || turn == null || json['moves'] is! List) {
      throw const FormatException('invalid draughts session');
    }
    final session = DraughtsSession(DraughtsRules.forVariant(variant));
    session.restore(
      position: DraughtsPosition.initial(session.rules),
      turn: session.rules.firstMove,
      history: (json['moves'] as List).map(DraughtsMove.fromJson).toList(),
      quietPlies: json['quietPlies'] is int ? json['quietPlies'] as int : 0,
      result: json['result'] == null
          ? null
          : DraughtsResult.fromJson(json['result']),
      keepUndo: true,
    );
    if (session.turn != turn ||
        json['position'] is! Map ||
        session.position.signature(session.turn) !=
            DraughtsPosition.fromJson(json['position']).signature(turn)) {
      throw const FormatException('saved position does not match move history');
    }
    return session;
  }
}

class _DraughtsSnapshot {
  const _DraughtsSnapshot({
    required this.position,
    required this.turn,
    required this.result,
    required this.quietPlies,
    required this.moveCount,
    required this.repetitions,
    required this.kingRaceSide,
    required this.kingRacePlies,
  });
  final DraughtsPosition position;
  final Side turn;
  final DraughtsResult? result;
  final int quietPlies;
  final int moveCount;
  final Map<String, int> repetitions;
  final Side? kingRaceSide;
  final int kingRacePlies;
}
