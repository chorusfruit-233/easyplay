import 'dart:math';

import '../game_session.dart' show Cell, Side, SideX;
import 'gomoku_ai_level.dart';
import 'gomoku_rules.dart';
import 'gomoku_session.dart';
import 'gomoku_player.dart';

export 'gomoku_ai_level.dart';
part 'gomoku_ai_position.dart';

class GomokuAiResult {
  const GomokuAiResult(this.cell, this.depth, this.nodes, {this.evaluation});
  final Cell cell;
  final int depth;
  final int nodes;

  /// Side-to-move score from a completed iteration or direct tactical proof.
  /// An interrupted search without a completed iteration has no evaluation.
  final int? evaluation;
}

/// Bounded local search with mandatory defense, forcing-line extensions and a
/// per-search transposition table. The live session is never used as scratch.
class GomokuAi implements GomokuPlayer {
  GomokuAi({Random? random}) : _random = random ?? Random();
  final Random _random;
  int _generation = 0;
  @override
  String? failureReason;

  @override
  void cancel() => _generation++;

  @override
  Future<void> dispose() async => cancel();

  T _choose<T>(List<T> choices) => choices.length == 1
      ? choices.first
      : choices[_random.nextInt(choices.length)];

  /// Opening actions belong to players, rather than the colour being placed.
  /// Normal play retains the tactical search and its cancellation budget.
  @override
  Future<GomokuAction?> decide(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
  }) async {
    if (source.gameOver) return null;
    if (source.phase == GomokuPhase.normal ||
        source.phase == GomokuPhase.fourth) {
      final result = await search(source, level: level);
      if (result != null) return GomokuAction.place(result.cell);
      return failureReason != null && source.canPass
          ? const GomokuAction.pass()
          : null;
    }
    final generation = ++_generation;
    failureReason = null;
    final session = source.fork();
    await Future<void>.delayed(Duration.zero);
    if (generation != _generation) return null;
    if (session.phase == GomokuPhase.opening) {
      // The rule core retains B1 at the centre and the prescribed W2/B3
      // regions. Derive each choice from the board, including resumed openings.
      final choices = [
        for (var row = 5; row <= 9; row++)
          for (var col = 5; col <= 9; col++)
            if (session.canPlace(Cell(row, col))) Cell(row, col),
      ];
      return choices.isEmpty ? null : GomokuAction.place(_choose(choices));
    }
    if (level == GomokuAiLevel.advanced) return _advancedOpening(session);
    return _heuristicOpening(session);
  }

  Future<GomokuAction?> _advancedOpening(GomokuSession session) async {
    Future<GomokuAiResult?> analyze(
      GomokuSession candidate,
      int branches,
    ) async {
      final pending = search(
        candidate,
        level: GomokuAiLevel.advanced,
        maxDepth: 3,
        maxNodes: GomokuAiLevel.advanced.nodes ~/ branches,
        timeLimit: Duration(
          milliseconds: GomokuAiLevel.advanced.milliseconds ~/ branches,
        ),
      );
      final generation = _generation;
      final result = await pending;
      return generation == _generation ? result : null;
    }

    if (session.phase == GomokuPhase.selection) {
      int? best;
      final choices = <Cell>[];
      for (final cell in session.proposals) {
        final candidate = session.fork()..place(cell);
        final result = await analyze(candidate, session.proposals.length);
        if (result == null) return null;
        final score = result.evaluation;
        if (score == null) return _heuristicOpening(session);
        if (best == null || score > best) {
          best = score;
          choices.clear();
        }
        if (score == best) choices.add(cell);
      }
      return choices.isEmpty ? null : GomokuAction.place(_choose(choices));
    }
    final result = await analyze(session, 1);
    if (result == null) return null;
    final score = result.evaluation;
    if (score == null) return _heuristicOpening(session);
    if (session.phase == GomokuPhase.exchange) {
      // Normal search lets black choose a free fifth move. A proven white win
      // remains valid when white can choose between two fifths. A black win
      // need not survive that constraint, so ordinary scores retain the book
      // decision instead of treating this approximation as the opening game.
      return score >= _Search.win - 1000
          ? const GomokuAction.exchange(false)
          : _heuristicOpening(session);
    }
    return GomokuAction.place(result.cell);
  }

  GomokuAction? _heuristicOpening(GomokuSession session) {
    final position = _Position(session);
    int value(int index, Side side) => position.pattern(index, side).score;
    if (session.phase == GomokuPhase.exchange) {
      var black = 0, white = 0;
      for (final index in position.nearbyCells()) {
        black = max(black, value(index, Side.black));
        white = max(white, value(index, Side.white));
      }
      return GomokuAction.exchange(black > white);
    }
    if (session.phase == GomokuPhase.selection) {
      final choices = List<Cell>.of(session.proposals)
        ..sort(
          (a, b) => value(
            a.row * 15 + a.col,
            Side.black,
          ).compareTo(value(b.row * 15 + b.col, Side.black)),
        );
      final best = value(
        choices.first.row * 15 + choices.first.col,
        Side.black,
      );
      return GomokuAction.place(
        _choose(
          choices
              .takeWhile(
                (cell) => value(cell.row * 15 + cell.col, Side.black) == best,
              )
              .toList(),
        ),
      );
    }
    if (session.phase == GomokuPhase.proposals) {
      final candidates = position
          .candidateCells()
          .where((i) => session.canPlace(position.cell(i)))
          .toList();
      candidates.sort(
        (a, b) => (value(b, Side.black) + value(b, Side.white)).compareTo(
          value(a, Side.black) + value(a, Side.white),
        ),
      );
      if (candidates.isNotEmpty) {
        int score(int index) =>
            value(index, Side.black) + value(index, Side.white);
        final best = score(candidates.first);
        return GomokuAction.place(
          position.cell(
            _choose(
              candidates.takeWhile((index) => score(index) == best).toList(),
            ),
          ),
        );
      }
    }
    return null;
  }

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
    final proposalSession = source.phase == GomokuPhase.proposals
        ? source.fork()
        : null;
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
          ? 12
          : level == GomokuAiLevel.intermediate
          ? 6
          : 2,
      varietyMargin: level == GomokuAiLevel.beginner ? 1500 : 0,
      advanced: level == GomokuAiLevel.advanced,
      rootAllowed: proposalSession == null
          ? null
          : (index) => proposalSession.canPlace(position.cell(index)),
    );
    await Future<void>.delayed(Duration.zero);
    if (generation != _generation) return null;
    final result = await search.run();
    if (generation != _generation) return null;
    if (search.noLegalMoves) failureReason = '棋盘上没有合法落点，可悔棋或认输';
    if (result == null) return null;
    // Stronger levels vary only proven equal scores from a completed iteration.
    // Entry-level keeps its wider quiet-move margin. Tactical roots are excluded.
    if (search.randomRoots.length > 1 &&
        (level != GomokuAiLevel.beginner || _random.nextDouble() < .75)) {
      return GomokuAiResult(
        position.cell(_choose(search.randomRoots)),
        result.depth,
        result.nodes,
        evaluation: level == GomokuAiLevel.beginner ? null : search.evaluation,
      );
    }
    return GomokuAiResult(
      result.cell,
      result.depth,
      result.nodes,
      evaluation: search.evaluation,
    );
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
    required this.varietyMargin,
    required this.advanced,
    this.rootAllowed,
  });
  static const win = 10000000;
  final _Position position;
  final bool Function() cancelled;
  final int maxNodes, maxDepth, candidateLimit, extension, varietyMargin;
  final bool advanced;
  final bool Function(int)? rootAllowed;
  int? evaluation;
  final Duration timeLimit;
  final clock = Stopwatch();
  final _table = <(int, int, Side), _Entry>{};
  final _frontiers = <(int, int, Side), _Frontier>{};
  final _killers = <int, List<int>>{};
  final _history = <(Side, int), int>{};
  final randomRoots = <int>[];
  int nodes = 0, operations = 0;
  bool noLegalMoves = false;

  List<_Move> _ordered(List<_Move> moves, int? preferred, int ply) {
    if (!advanced || moves.length < 2) return moves;
    final killers = _killers[ply] ?? const <int>[];
    int priority(_Move move) =>
        (move.index == preferred ? 100000000 : 0) +
        (move.attack.forcing ? 10000000 : 0) +
        move.order +
        (killers.contains(move.index) ? 2000 : 0) +
        (_history[(position.turn, move.index)] ?? 0);
    return List<_Move>.of(moves)..sort((a, b) {
      final score = priority(b).compareTo(priority(a));
      return score != 0 ? score : a.index.compareTo(b.index);
    });
  }

  void _cutoff(_Move move, int depth, int ply) {
    if (!advanced || depth <= 0 || move.attack.forcing) return;
    final killers = _killers.putIfAbsent(ply, () => []);
    killers.remove(move.index);
    killers.insert(0, move.index);
    if (killers.length > 2) killers.removeLast();
    final key = (position.turn, move.index);
    _history[key] = min(2000, (_history[key] ?? 0) + depth * depth * 4);
  }

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
      if (rootAllowed != null && !rootAllowed!(move)) continue;
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
      if (rootAllowed != null &&
          position._undo.isEmpty &&
          !rootAllowed!(index)) {
        continue;
      }
      await _poll();
      var attack = position.pattern(index, position.turn);
      var defense = position.pattern(index, position.turn.opponent);
      if (position.variant.hasForbiddenMoves &&
          position.turn == Side.black &&
          (attack.forcing || attack.threes >= 2) &&
          !position.analysis(index, Side.black, _check).legal) {
        attack = const _Pattern();
      }
      // A black Renju fork may itself be forbidden. Never spend a mandatory
      // defense on a point the opponent cannot legally play.
      if (position.variant.hasForbiddenMoves &&
          position.turn == Side.white &&
          (defense.forcing || defense.threes >= 2) &&
          !position.analysis(index, Side.black, _check).legal) {
        defense = const _Pattern();
      }
      if (attack.wins) ownWins.add(index);
      if (defense.wins) enemyWins.add(index);
      danger |= defense.fork || attack.forcing;
      if (defense.fork) {
        if (position.variant.hasForbiddenMoves &&
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
        if (root.wins) evaluation = win - 1;
        if (root.fork) evaluation = win - 3;
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
      final moves = List<_Move>.of(_ordered(root.moves, best, 0));
      final pv = moves.indexWhere((move) => move.index == best);
      if (pv > 0) moves.insert(0, moves.removeAt(pv));
      try {
        for (final move in moves) {
          _check();
          final won = position.place(move);
          late int value;
          try {
            if (won) {
              value = win - 1;
            } else if (advanced && scores.isNotEmpty) {
              // The two-point scout window proves ties as well as improvements.
              // A fail-high improvement is re-searched before it can be chosen.
              value = -await _negamax(
                depth - 1,
                -score - 1,
                -score + 1,
                1,
                extension,
              );
              if (value > score) {
                value = -await _negamax(
                  depth - 1,
                  -win * 2,
                  -score + 1,
                  1,
                  extension,
                );
              }
            } else {
              value = -await _negamax(
                depth - 1,
                -win * 2,
                // A cutoff at -score can look tied while hiding a worse
                // reply. Search past the entire selectable score band.
                -score + varietyMargin + 1,
                1,
                extension,
              );
            }
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
      evaluation = score;
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
                    lastScores[m.index]! >= bestScore - varietyMargin &&
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
    var moves = _ordered(frontier.moves, entry?.move, ply);
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
    var searched = 0;
    for (final move in moves) {
      final won = position.place(move);
      late int score;
      try {
        if (won) {
          score = win - ply - 1;
        } else if (advanced && searched > 0) {
          score = -await _negamax(
            depth - 1,
            -alpha - 1,
            -alpha,
            ply + 1,
            extensionLeft - (depth <= 0 ? 1 : 0),
          );
          if (score > alpha && score < beta) {
            score = -await _negamax(
              depth - 1,
              -beta,
              -alpha,
              ply + 1,
              extensionLeft - (depth <= 0 ? 1 : 0),
            );
          }
        } else {
          score = -await _negamax(
            depth - 1,
            -beta,
            -alpha,
            ply + 1,
            extensionLeft - (depth <= 0 ? 1 : 0),
          );
        }
      } finally {
        position.undo();
      }
      if (score > best) {
        best = score;
        bestMove = move.index;
      }
      searched++;
      alpha = max(alpha, score);
      if (alpha >= beta) {
        _cutoff(move, depth, ply);
        break;
      }
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
