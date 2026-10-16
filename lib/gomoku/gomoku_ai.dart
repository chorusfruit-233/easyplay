import 'dart:math';

import '../game_session.dart' show Cell, Side, SideX;
import 'gomoku_ai_level.dart';
import 'gomoku_rules.dart';
import 'gomoku_session.dart';

export 'gomoku_ai_level.dart';
part 'gomoku_ai_position.dart';

class GomokuAiResult {
  const GomokuAiResult(this.cell, this.depth, this.nodes);
  final Cell cell;
  final int depth;
  final int nodes;
}

/// Bounded local search with mandatory defense, forcing-line extensions and a
/// per-search transposition table. The live session is never used as scratch.
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
      candidateLimit: level == GomokuAiLevel.advanced
          ? 14
          : level == GomokuAiLevel.intermediate
          ? 10
          : 8,
      extension: level == GomokuAiLevel.advanced
          ? 8
          : level == GomokuAiLevel.intermediate
          ? 6
          : 2,
    );
    await Future<void>.delayed(Duration.zero);
    if (generation != _generation) return null;
    final result = await search.run();
    if (generation != _generation) return null;
    if (search.noLegalMoves) failureReason = '棋盘上没有合法落点，可悔棋或认输';
    if (result == null) return null;
    // Entry-level variety belongs only to quiet, searched-safe moves. A win,
    // required block, forcing line or known losing reply is never randomized.
    if (level == GomokuAiLevel.beginner &&
        search.randomRoots.length > 1 &&
        _random.nextDouble() < .75) {
      return GomokuAiResult(
        position.cell(
          search.randomRoots[_random.nextInt(search.randomRoots.length)],
        ),
        result.depth,
        result.nodes,
      );
    }
    return result;
  }
}

class _SearchStopped implements Exception {}

enum _Bound { exact, lower, upper }

class _Entry {
  const _Entry(this.depth, this.score, this.bound, this.move);
  final int depth;
  final int score;
  final _Bound bound;
  final int move;
}

class _Frontier {
  const _Frontier(
    this.moves,
    this.evaluation, {
    this.wins = false,
    this.fork = false,
    this.forced = false,
    this.lost = false,
    this.forkLoss = false,
    this.threatened = false,
    this.danger = false,
  });
  final List<_Move> moves;
  final int evaluation;
  final bool wins, fork, forced, lost, forkLoss, threatened, danger;

  _Frontier prefer(int? index) {
    if (index == null) return this;
    final at = moves.indexWhere((move) => move.index == index);
    if (at <= 0) return this;
    final ordered = List<_Move>.of(moves);
    ordered.insert(0, ordered.removeAt(at));
    return _Frontier(
      ordered,
      evaluation,
      wins: wins,
      fork: fork,
      forced: forced,
      lost: lost,
      forkLoss: forkLoss,
      threatened: threatened,
      danger: danger,
    );
  }
}

class _Search {
  _Search(
    this.position, {
    required this.cancelled,
    required this.maxNodes,
    required this.maxDepth,
    required this.timeLimit,
    required this.candidateLimit,
    required this.extension,
  });
  static const win = 10000000;
  final _Position position;
  final bool Function() cancelled;
  final int maxNodes, maxDepth, candidateLimit, extension;
  final Duration timeLimit;
  final clock = Stopwatch();
  final _table = <(int, int, Side), _Entry>{};
  final _frontiers = <(int, int, Side), _Frontier>{};
  final randomRoots = <int>[];
  int nodes = 0, operations = 0;
  bool noLegalMoves = false;

  void _check() {
    if (cancelled() || clock.elapsed >= timeLimit) throw _SearchStopped();
  }

  Future<void> _poll() async {
    if (operations++ % 32 == 0) await Future<void>.delayed(Duration.zero);
    _check();
  }

  Future<void> _visit() async {
    if (nodes % 32 == 0) await Future<void>.delayed(Duration.zero);
    _check();
    if (nodes >= maxNodes) throw _SearchStopped();
    nodes++;
  }

  Future<int?> _firstLegal() async {
    for (final move in position.candidateCells()) {
      if (operations++ % 16 == 0) await Future<void>.delayed(Duration.zero);
      final analysis = position.analysis(move, position.turn, () {
        if (cancelled()) throw _SearchStopped();
      });
      if (analysis.legal) return move;
    }
    return null;
  }

  Future<_Frontier> _frontier([int? preferred]) async {
    final key = position.key;
    var result = _frontiers[key];
    if (result == null) {
      result = await _buildFrontier();
      // Bound memory independently of user-supplied node limits.
      if (_frontiers.length < 4096) _frontiers[key] = result;
    }
    return result.prefer(preferred);
  }

  Future<_Frontier> _buildFrontier() async {
    final scored = <(int, _Pattern, _Pattern, int)>[];
    final ownWins = <int>[], enemyWins = <int>[];
    var ownBest = 0, ownSecond = 0, enemyBest = 0, enemySecond = 0;
    var danger = false;
    Set<int>? defenses;
    var stableDefenses = true;
    for (final index in position.nearbyCells()) {
      await _poll();
      var attack = position.pattern(index, position.turn);
      var defense = position.pattern(index, position.turn.opponent);
      if (position.variant == GomokuVariant.renju &&
          position.turn == Side.black &&
          (attack.forcing || attack.threes >= 2) &&
          !position.analysis(index, Side.black, _check).legal) {
        attack = const _Pattern();
      }
      // A black Renju fork may itself be forbidden. Never spend a mandatory
      // defense on a point the opponent cannot legally play.
      if (position.variant == GomokuVariant.renju &&
          position.turn == Side.white &&
          (defense.forcing || defense.threes >= 2) &&
          !position.analysis(index, Side.black, _check).legal) {
        defense = const _Pattern();
      }
      if (attack.wins) ownWins.add(index);
      if (defense.wins) enemyWins.add(index);
      danger |= defense.fork || attack.forcing;
      if (defense.fork) {
        if (position.variant == GomokuVariant.renju &&
            position.turn == Side.white &&
            defense.threes >= 2) {
          stableDefenses = false;
        }
        // Prevent every possible open-four fork, either at its creation point
        // or at an endpoint. A counter-four can also take back the initiative.
        final answers = {
          index,
          if (defense.winningPoints.length == 2) ...defense.winningPoints,
        };
        defenses = defenses == null ? answers : defenses.intersection(answers);
      }
      if (attack.score > ownBest) {
        ownSecond = ownBest;
        ownBest = attack.score;
      } else if (attack.score > ownSecond) {
        ownSecond = attack.score;
      }
      if (defense.score > enemyBest) {
        enemySecond = enemyBest;
        enemyBest = defense.score;
      } else if (defense.score > enemySecond) {
        enemySecond = defense.score;
      }
      scored.add((
        index,
        attack,
        defense,
        attack.score + defense.score * 11 ~/ 10,
      ));
    }
    scored.sort((a, b) {
      final score = b.$4.compareTo(a.$4);
      return score != 0 ? score : a.$1.compareTo(b.$1);
    });
    _Move? legal((int, _Pattern, _Pattern, int) item) {
      final analysis = position.analysis(item.$1, position.turn, _check);
      return analysis.legal
          ? _Move(item.$1, analysis, item.$2, item.$3, item.$4)
          : null;
    }

    final evaluation =
        (ownBest + ownSecond ~/ 4 - enemyBest * 11 ~/ 10 - enemySecond ~/ 4)
            .clamp(-win ~/ 2, win ~/ 2);
    if (ownWins.isNotEmpty) {
      final moves = [
        for (final s in scored)
          if (s.$2.wins) ?legal(s),
      ];
      if (moves.isNotEmpty) {
        return _Frontier(moves, evaluation, wins: true, danger: true);
      }
    }
    if (enemyWins.isNotEmpty) {
      final moves = [
        for (final s in scored)
          if (s.$3.wins) ?legal(s),
      ];
      return _Frontier(
        moves,
        evaluation,
        forced: true,
        lost: enemyWins.length > 1 || moves.isEmpty,
        danger: true,
      );
    }
    final forks = [
      for (final s in scored)
        if (s.$2.fork) ?legal(s),
    ];
    if (forks.isNotEmpty) {
      return _Frontier(forks, evaluation, fork: true, danger: true);
    }
    final moves = <_Move>[];
    // A white defense can change recursive fake threes. Keep the wider frontier
    // if a legal black fork has multiple geometric threes; otherwise adding an
    // opposing stone cannot turn that fork into a new double-three forbidden move.
    final pruneDefense = defenses != null && stableDefenses;
    for (final item in scored) {
      if (pruneDefense && !defenses.contains(item.$1) && !item.$2.forcing) {
        continue;
      }
      if (moves.length >= candidateLimit && !item.$2.forcing) continue;
      final move = legal(item);
      if (move != null) moves.add(move);
    }
    if (pruneDefense && moves.isEmpty) {
      for (final item in scored) {
        final move = legal(item);
        if (move != null) {
          moves.add(move);
          break;
        }
      }
      return _Frontier(
        moves,
        evaluation,
        forkLoss: true,
        danger: true,
        threatened: true,
      );
    }
    return _Frontier(
      moves,
      evaluation,
      danger: danger,
      threatened: defenses != null,
    );
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
    var best = fallback, completedDepth = 0;
    if (maxDepth == 0 || maxNodes == 0 || timeLimit <= Duration.zero) {
      return GomokuAiResult(position.cell(best), 0, 0);
    }
    late _Frontier root;
    try {
      await _visit();
      root = await _frontier();
      if (root.moves.isEmpty) {
        return GomokuAiResult(position.cell(best), 0, nodes);
      }
      best = root.moves.first.index;
      if (root.wins || root.fork || root.forced || root.forkLoss) {
        return GomokuAiResult(position.cell(best), 1, nodes);
      }
      if (root.danger) {
        // Check every candidate's immediate tactical safety before spending the
        // remaining budget on a long forcing line in the first branch.
        final safe = <_Move>[];
        for (final move in root.moves) {
          await _visit();
          position.place(move);
          late _Frontier reply;
          try {
            reply = await _frontier();
          } finally {
            position.undo();
          }
          if (!reply.wins && !reply.fork) {
            safe.add(move);
            best = safe.first.index;
          }
        }
        if (safe.isNotEmpty) {
          root = _Frontier(
            safe,
            root.evaluation,
            danger: true,
            threatened: root.threatened,
          );
        }
      }
    } on _SearchStopped {
      return GomokuAiResult(position.cell(best), 0, nodes);
    }
    Map<int, int> lastScores = {};
    for (var depth = 1; depth <= maxDepth; depth++) {
      var score = -win * 2, candidate = best;
      final scores = <int, int>{};
      final moves = List<_Move>.of(root.moves);
      final pv = moves.indexWhere((move) => move.index == best);
      if (pv > 0) moves.insert(0, moves.removeAt(pv));
      try {
        for (final move in moves) {
          _check();
          final won = position.place(move);
          late int value;
          try {
            value = won
                ? win - 1
                : -await _negamax(depth - 1, -win * 2, -score, 1, extension);
          } finally {
            position.undo();
          }
          scores[move.index] = value;
          if (value > score) {
            score = value;
            candidate = move.index;
          }
        }
      } on _SearchStopped {
        // Keep a completed tactical proof if the first iteration is interrupted.
        if (completedDepth == 0 && scores.isNotEmpty) best = candidate;
        break;
      }
      best = candidate;
      lastScores = scores;
      completedDepth = depth;
      if (score.abs() >= win - 1000) break;
    }
    if (!root.danger && lastScores.isNotEmpty) {
      final bestScore = lastScores[best]!;
      if (bestScore.abs() < win - 1000) {
        randomRoots.addAll(
          root.moves
              .where(
                (m) =>
                    lastScores[m.index] != null &&
                    lastScores[m.index]! >= bestScore - 1500 &&
                    lastScores[m.index]!.abs() < win - 1000,
              )
              .take(6)
              .map((m) => m.index),
        );
      }
    }
    return GomokuAiResult(position.cell(best), completedDepth, nodes);
  }

  int _storeScore(int score, int ply) => score >= win - 1000
      ? score + ply
      : score <= -win + 1000
      ? score - ply
      : score;
  int _loadScore(int score, int ply) => score >= win - 1000
      ? score - ply
      : score <= -win + 1000
      ? score + ply
      : score;

  Future<int> _negamax(
    int depth,
    int alpha,
    int beta,
    int ply,
    int extensionLeft,
  ) async {
    await _visit();
    if (position.count == gomokuBoardSize * gomokuBoardSize) return 0;
    final key = position.key, originalAlpha = alpha;
    final entry = _table[key];
    if (depth > 0 && entry != null && entry.depth >= depth) {
      final score = _loadScore(entry.score, ply);
      if (entry.bound == _Bound.exact) return score;
      if (entry.bound == _Bound.lower) alpha = max(alpha, score);
      if (entry.bound == _Bound.upper) beta = min(beta, score);
      if (alpha >= beta) return score;
    }
    final frontier = await _frontier(entry?.move);
    if (frontier.wins) return win - ply - 1;
    if (frontier.lost) return -win + ply + 2;
    if (frontier.forkLoss) return -win + ply + 4;
    if (frontier.fork) return win - ply - 3;
    if (frontier.moves.isEmpty) return -win + ply;
    var moves = frontier.moves;
    var best = -win * 2;
    if (depth <= 0) {
      if (extensionLeft <= 0) return frontier.evaluation;
      if (!frontier.forced && !frontier.threatened) {
        // Quiet positions may stand pat, but never while a block is required.
        best = frontier.evaluation;
        if (best >= beta) return best;
        alpha = max(alpha, best);
        moves = moves.where((move) => move.attack.forcing).take(6).toList();
        if (moves.isEmpty) return best;
      }
    }
    var bestMove = moves.first.index;
    for (final move in moves) {
      final won = position.place(move);
      late int score;
      try {
        score = won
            ? win - ply - 1
            : -await _negamax(
                depth - 1,
                -beta,
                -alpha,
                ply + 1,
                extensionLeft - (depth <= 0 ? 1 : 0),
              );
      } finally {
        position.undo();
      }
      if (score > best) {
        best = score;
        bestMove = move.index;
      }
      alpha = max(alpha, score);
      if (alpha >= beta) break;
    }
    if (depth > 0) {
      final bound = best <= originalAlpha
          ? _Bound.upper
          : best >= beta
          ? _Bound.lower
          : _Bound.exact;
      if (entry == null || depth >= entry.depth) {
        _table[key] = _Entry(depth, _storeScore(best, ply), bound, bestMove);
      }
    }
    return best;
  }
}
