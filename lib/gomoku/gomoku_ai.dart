import 'dart:math';

import '../game_session.dart' show Cell, Side, SideX;
import 'gomoku_ai_level.dart';
import 'gomoku_rules.dart';
import 'gomoku_session.dart';

export 'gomoku_ai_level.dart';

class GomokuAiResult {
  const GomokuAiResult(this.cell, this.depth, this.nodes);
  final Cell cell;
  final int depth;
  final int nodes;
}

/// Local, portable search. The private position never changes the live session,
/// and small batches yield on both native and Web so cancellation stays usable.
class GomokuAi {
  GomokuAi({Random? random}) : _random = random ?? Random();

  final Random _random;
  int _generation = 0;
  String? failureReason;

  void cancel() => _generation++;

  Future<GomokuAiResult?> search(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
    int? maxNodes,
    int? maxDepth,
    Duration? timeLimit,
  }) async {
    final generation = ++_generation;
    failureReason = null;
    if (source.gameOver) return null;
    final position = _Position(source);
    final search = _Search(
      position,
      cancelled: () => generation != _generation,
      maxNodes: max(0, maxNodes ?? level.nodes),
      maxDepth: max(0, maxDepth ?? level.depth),
      timeLimit: timeLimit ?? Duration(milliseconds: level.milliseconds),
      beginner: level == GomokuAiLevel.beginner,
      candidateLimit: level == GomokuAiLevel.advanced ? 14 : 10,
    );
    await Future<void>.delayed(Duration.zero);
    if (generation != _generation) return null;
    final result = await search.run();
    if (generation != _generation) return null;
    if (search.noLegalMoves) failureReason = '棋盘上没有合法落点，可悔棋或认输';
    if (result == null) return null;
    if (level == GomokuAiLevel.beginner && _random.nextDouble() < 0.75) {
      final choices = search.legalRoots;
      return GomokuAiResult(
        position.cell(choices[_random.nextInt(choices.length)]),
        result.depth,
        result.nodes,
      );
    }
    return result;
  }
}

class _SearchStopped implements Exception {}

class _Candidate {
  const _Candidate(this.index, this.analysis);
  final int index;
  final GomokuMoveAnalysis analysis;
}

class _Search {
  _Search(
    this.position, {
    required this.cancelled,
    required this.maxNodes,
    required this.maxDepth,
    required this.timeLimit,
    required this.beginner,
    required this.candidateLimit,
  });

  final _Position position;
  final bool Function() cancelled;
  final int maxNodes;
  final int maxDepth;
  final Duration timeLimit;
  final bool beginner;
  final int candidateLimit;
  final Stopwatch clock = Stopwatch();
  int nodes = 0;
  int operations = 0;
  final List<int> legalRoots = [];
  bool noLegalMoves = false;
  static const win = 10000000;

  void _checkBudget() {
    if (cancelled() || clock.elapsed >= timeLimit) throw _SearchStopped();
  }

  Future<void> _checkCandidates() async {
    if (operations++ % 16 == 0) await Future<void>.delayed(Duration.zero);
    _checkBudget();
  }

  Future<void> _visit() async {
    if (nodes % 16 == 0) await Future<void>.delayed(Duration.zero);
    if (cancelled() || nodes >= maxNodes || clock.elapsed >= timeLimit) {
      throw _SearchStopped();
    }
    nodes++;
  }

  Future<List<_Candidate>> _ordered([int? preferred]) async {
    final choices = position.nearbyCells();
    final scores = <int, int>{};
    final legal = <_Candidate>[];
    Future<void> collect(Iterable<int> candidates) async {
      for (final move in candidates) {
        await _checkCandidates();
        final analysis = position.analysis(move, position.turn, _checkBudget);
        if (!analysis.legal) continue;
        legal.add(_Candidate(move, analysis));
        if (position.count == position.initialCount &&
            !legalRoots.contains(move)) {
          legalRoots.add(move);
        }
        final other = beginner
            ? null
            : position.analysis(move, position.turn.opponent, _checkBudget);
        scores[move] =
            position.moveValue(move, position.turn, analysis) +
            (other == null
                ? 0
                : position.moveValue(move, position.turn.opponent, other));
      }
    }

    await collect(choices);
    if (legal.isEmpty) {
      await collect(
        position.candidateCells().where((move) => !choices.contains(move)),
      );
    }
    legal.sort((a, b) {
      if (a.index == preferred) return -1;
      if (b.index == preferred) return 1;
      final score = scores[b.index]!.compareTo(scores[a.index]!);
      return score != 0 ? score : a.index.compareTo(b.index);
    });
    return legal.take(candidateLimit).toList();
  }

  Future<int?> _firstLegal() async {
    for (final move in position.candidateCells()) {
      if (operations++ % 16 == 0) await Future<void>.delayed(Duration.zero);
      if (cancelled()) throw _SearchStopped();
      final analysis = position.analysis(move, position.turn, () {
        if (cancelled()) throw _SearchStopped();
        if (timeLimit > Duration.zero) _checkBudget();
      });
      if (analysis.legal) {
        legalRoots.add(move);
        return move;
      }
    }
    return null;
  }

  Future<int?> _immediateWin(Side side) async {
    for (final move in position.nearbyCells()) {
      await _checkCandidates();
      final analysis = position.analysis(move, side, _checkBudget);
      if (!analysis.legal || analysis.winningLine.isEmpty) continue;
      // A black Renju player may be unable to occupy White's winning point.
      if (position.analysis(move, position.turn, _checkBudget).legal) {
        return move;
      }
    }
    return null;
  }

  Future<GomokuAiResult?> run() async {
    clock.start();
    int? fallback;
    try {
      fallback = await _firstLegal();
    } on _SearchStopped {
      return null;
    }
    if (fallback == null) {
      noLegalMoves = true;
      return null;
    }
    var best = fallback;
    var completedDepth = 0;
    if (maxDepth == 0 || maxNodes == 0 || timeLimit <= Duration.zero) {
      return GomokuAiResult(position.cell(best), 0, 0);
    }
    // Tactical checks precede the reduced search frontier: a winning move or
    // a required immediate block must never disappear from the candidate list.
    if (!beginner) {
      try {
        await _visit();
        for (final side in [position.turn, position.turn.opponent]) {
          final threat = await _immediateWin(side);
          if (threat != null) {
            return GomokuAiResult(position.cell(threat), 1, nodes);
          }
        }
      } on _SearchStopped {
        return GomokuAiResult(position.cell(best), 0, nodes);
      }
    }
    try {
      final initial = await _ordered();
      if (initial.isEmpty) return GomokuAiResult(position.cell(best), 0, nodes);
      best = initial.first.index;
    } on _SearchStopped {
      return GomokuAiResult(position.cell(best), 0, nodes);
    }
    for (var depth = 1; depth <= maxDepth; depth++) {
      var score = -win * 2;
      var candidate = best;
      try {
        for (final move in await _ordered(best)) {
          await _visit();
          final won = position.place(move);
          late final int value;
          try {
            value = won
                ? win - 1
                : -await _negamax(depth - 1, -win * 2, -score, 1);
          } finally {
            position.undo(move.index);
          }
          if (value > score) {
            score = value;
            candidate = move.index;
          }
        }
      } on _SearchStopped {
        break;
      }
      best = candidate;
      completedDepth = depth;
      if (score.abs() >= win - 1000) break;
    }
    return GomokuAiResult(position.cell(best), completedDepth, nodes);
  }

  Future<int> _negamax(int depth, int alpha, int beta, int ply) async {
    await _visit();
    if (position.count == gomokuBoardSize * gomokuBoardSize) return 0;
    if (depth <= 0) return position.evaluate();
    var best = -win * 2;
    final choices = await _ordered();
    if (choices.isEmpty) return -win + ply;
    for (final move in choices) {
      final won = position.place(move);
      late final int score;
      try {
        score = won
            ? win - ply - 1
            : -await _negamax(depth - 1, -beta, -alpha, ply + 1);
      } finally {
        position.undo(move.index);
      }
      if (score > best) best = score;
      if (score > alpha) alpha = score;
      if (alpha >= beta) break;
    }
    return best;
  }
}

class _Position {
  _Position(GomokuSession session)
    : board = [
        for (var row = 0; row < gomokuBoardSize; row++)
          for (var col = 0; col < gomokuBoardSize; col++)
            session.pieceAt(Cell(row, col)),
      ],
      turn = session.turn,
      count = session.moves.length,
      initialCount = session.moves.length,
      variant = session.variant;

  static const size = gomokuBoardSize;
  static const directions = [(0, 1), (1, 0), (1, 1), (1, -1)];
  final List<Side?> board;
  final GomokuVariant variant;
  final int initialCount;
  final Map<(int, Side), GomokuMoveAnalysis> _analysis = {};
  Side turn;
  int count;

  Cell cell(int index) => Cell(index ~/ size, index % size);
  bool inside(int row, int col) =>
      row >= 0 && col >= 0 && row < size && col < size;

  List<int> nearbyCells() {
    if (count == 0) return [(size ~/ 2) * size + size ~/ 2];
    final candidates = <int>{};
    for (var index = 0; index < board.length; index++) {
      if (board[index] == null) continue;
      final row = index ~/ size;
      final col = index % size;
      for (var dr = -2; dr <= 2; dr++) {
        for (var dc = -2; dc <= 2; dc++) {
          final nextRow = row + dr;
          final nextCol = col + dc;
          if (inside(nextRow, nextCol)) {
            final next = nextRow * size + nextCol;
            if (board[next] == null) candidates.add(next);
          }
        }
      }
    }
    return candidates.toList();
  }

  Iterable<int> candidateCells() sync* {
    final nearby = nearbyCells().toSet();
    yield* nearby;
    for (var index = 0; index < board.length; index++) {
      if (board[index] == null && !nearby.contains(index)) yield index;
    }
  }

  GomokuMoveAnalysis analysis(
    int index,
    Side side,
    void Function() checkBudget,
  ) => _analysis.putIfAbsent(
    (index, side),
    () => analyzeGomokuMove(
      board,
      cell(index),
      side,
      variant: variant,
      checkBudget: checkBudget,
    ),
  );

  bool place(_Candidate move) {
    if (!move.analysis.legal) throw StateError('AI candidate is illegal');
    board[move.index] = turn;
    final won = move.analysis.winningLine.isNotEmpty;
    turn = turn.opponent;
    count++;
    _analysis.clear();
    return won;
  }

  void undo(int index) {
    board[index] = null;
    turn = turn.opponent;
    count--;
    _analysis.clear();
  }

  int moveValue(int index, Side side, GomokuMoveAnalysis analysis) {
    if (!analysis.legal) return 0;
    if (analysis.winningLine.isNotEmpty) return _Search.win;
    board[index] = side;
    final row = index ~/ size;
    final col = index % size;
    var value = size - (row - size ~/ 2).abs() - (col - size ~/ 2).abs();
    for (final (dr, dc) in directions) {
      var length = 1;
      var open = 0;
      for (final sign in [-1, 1]) {
        var step = 1;
        while (true) {
          final r = row + dr * step * sign;
          final c = col + dc * step * sign;
          if (!inside(r, c)) break;
          if (board[r * size + c] == side) {
            length++;
            step++;
          } else {
            if (board[r * size + c] == null) open++;
            break;
          }
        }
      }
      value += switch (length) {
        >= 5 => 0,
        4 => open == 2 ? 60000 : (open == 1 ? 12000 : 0),
        3 => open == 2 ? 2000 : (open == 1 ? 250 : 0),
        2 => open == 2 ? 60 : (open == 1 ? 10 : 0),
        _ => open,
      };
      // Include broken fours/threes, not just contiguous stone runs.
      for (var offset = -4; offset <= 0; offset++) {
        var stones = 0;
        var available = true;
        for (var step = 0; step < 5; step++) {
          final r = row + dr * (offset + step);
          final c = col + dc * (offset + step);
          if (!inside(r, c) || board[r * size + c] == side.opponent) {
            available = false;
            break;
          }
          if (board[r * size + c] == side) stones++;
        }
        if (available) value += [0, 0, 2, 100, 6000, 0][stones];
      }
    }
    board[index] = null;
    return value;
  }

  int evaluate() {
    var value = 0;
    const weights = [0, 1, 10, 150, 6000, 0];
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        for (final (dr, dc) in directions) {
          if (!inside(row + dr * 4, col + dc * 4)) continue;
          var own = 0;
          var opponent = 0;
          for (var step = 0; step < 5; step++) {
            final side = board[(row + dr * step) * size + col + dc * step];
            if (side == turn) own++;
            if (side == turn.opponent) opponent++;
          }
          if (opponent == 0) value += weights[own];
          if (own == 0) value -= weights[opponent];
        }
      }
    }
    return value;
  }
}
