import 'dart:math';

import '../game_session.dart' show Cell, Side;
import 'draughts_ai_level.dart';
import 'draughts_move.dart';
import 'draughts_piece.dart';
import 'draughts_rules.dart';
import 'draughts_session.dart';

class DraughtsAiResult {
  const DraughtsAiResult(this.move, this.depth, this.nodes);
  final DraughtsMove move;
  final int depth;
  final int nodes;
}

/// Portable, bounded negamax search. Work yields to the event loop between
/// small batches on both native and Web, allowing cancellation and UI updates.
/// All transitions, draw counters and capture paths belong to DraughtsSession.
class DraughtsAi {
  DraughtsAi({Random? random}) : _random = random ?? Random();

  final Random _random;
  int _generation = 0;
  void cancel() => _generation++;

  Future<DraughtsAiResult?> search(
    DraughtsSession source, {
    DraughtsAiLevel level = DraughtsAiLevel.intermediate,
    int? maxNodes,
    int? maxDepth,
    Duration? timeLimit,
  }) async {
    final generation = ++_generation;
    final session = source.fork();
    final moves = session.legalMoves();
    if (moves.isEmpty) return null;
    final search = _Search(
      session,
      cancelled: () => generation != _generation,
      maxNodes: maxNodes ?? level.nodes,
      maxDepth: maxDepth ?? level.depth,
      timeLimit: timeLimit ?? Duration(milliseconds: level.milliseconds),
      captureExtension: level == DraughtsAiLevel.beginner
          ? 0
          : level == DraughtsAiLevel.advanced
          ? 10
          : 6,
      advanced: level == DraughtsAiLevel.advanced,
    );
    await Future<void>.delayed(Duration.zero);
    final result = await search.run();
    if (generation != _generation) return null;
    // Entry-level practice deliberately overlooks tactics. Random moves come
    // from the rule-filtered list, including mandatory complete capture paths.
    if (level == DraughtsAiLevel.beginner && _random.nextDouble() < 0.75) {
      return DraughtsAiResult(
        moves[_random.nextInt(moves.length)],
        result.depth,
        result.nodes,
      );
    }
    if (level != DraughtsAiLevel.beginner && search.equalMoves.length > 1) {
      return DraughtsAiResult(
        search.equalMoves[_random.nextInt(search.equalMoves.length)],
        result.depth,
        result.nodes,
      );
    }
    return result;
  }
}

class _SearchStopped implements Exception {}

class _Search {
  _Search(
    this.session, {
    required this.cancelled,
    required this.maxNodes,
    required this.maxDepth,
    required this.timeLimit,
    required this.captureExtension,
    required this.advanced,
  });

  final DraughtsSession session;
  final bool Function() cancelled;
  final int maxNodes;
  final int maxDepth;
  final Duration timeLimit;
  final int captureExtension;
  final bool advanced;
  final Stopwatch clock = Stopwatch();
  final equalMoves = <DraughtsMove>[];
  final _killers = <int, List<DraughtsMove>>{};
  final _history = <(Side, Cell, Cell), int>{};
  int nodes = 0;
  static const win = 100000;

  Future<void> _visit() async {
    if (nodes % 16 == 0) await Future<void>.delayed(Duration.zero);
    if (cancelled() || nodes >= maxNodes || clock.elapsed >= timeLimit) {
      throw _SearchStopped();
    }
    nodes++;
  }

  List<DraughtsMove> _ordered([DraughtsMove? preferred, int ply = 0]) {
    final moves = List<DraughtsMove>.of(session.legalMoves());
    int priority(DraughtsMove m) =>
        (m == preferred ? 10000 : 0) +
        m.captures.length * 100 +
        (session.rules.isPromotionCell(session.turn, m.to) ? 30 : 0) +
        (advanced && !m.isCapture
            ? ((_killers[ply]?.contains(m) ?? false) ? 24 : 0) +
                  (_history[(session.turn, m.from, m.to)] ?? 0)
            : 0);
    moves.sort((a, b) => priority(b).compareTo(priority(a)));
    return moves;
  }

  void _cutoff(DraughtsMove move, int depth, int ply) {
    if (!advanced || depth <= 0 || move.isCapture) return;
    final killers = _killers.putIfAbsent(ply, () => []);
    killers.remove(move);
    killers.insert(0, move);
    if (killers.length > 2) killers.removeLast();
    final key = (session.turn, move.from, move.to);
    _history[key] = min(24, (_history[key] ?? 0) + depth * depth);
  }

  Future<DraughtsAiResult> run() async {
    clock.start();
    var best = _ordered().first;
    var completedDepth = 0;
    for (var depth = 1; depth <= maxDepth; depth++) {
      var score = -win * 2;
      var candidate = best;
      final ties = <DraughtsMove>[];
      try {
        for (final move in _ordered(best)) {
          await _visit();
          session.applyMove(move);
          late int value;
          try {
            if (advanced && ties.isNotEmpty) {
              value = -await _negamax(
                depth - 1,
                -score - 1,
                -score + 1,
                1,
                captureExtension,
              );
              if (value > score) {
                value = -await _negamax(
                  depth - 1,
                  -win * 2,
                  -score + 1,
                  1,
                  captureExtension,
                );
              }
            } else {
              value = -await _negamax(
                depth - 1,
                -win * 2,
                // Equal-score alternatives must be exact, not a cutoff bound
                // hiding an opponent's stronger reply.
                -score + 1,
                1,
                captureExtension,
              );
            }
          } finally {
            session.undo();
          }
          if (value > score) {
            score = value;
            candidate = move;
            ties.clear();
          }
          if (value == score) ties.add(move);
        }
      } on _SearchStopped {
        break;
      }
      best = candidate;
      completedDepth = depth;
      // An interrupted deeper iteration retains the last completed choices.
      equalMoves
        ..clear()
        ..addAll(ties);
      if (score.abs() >= win - 1000) break;
    }
    return DraughtsAiResult(best, completedDepth, nodes);
  }

  Future<int> _negamax(
    int depth,
    int alpha,
    int beta,
    int ply,
    int captureExtension,
  ) async {
    await _visit();
    final result = session.result;
    if (result != null) {
      if (result.winner == null) return 0;
      return result.winner == session.turn ? win - ply : -win + ply;
    }
    final moves = _ordered(null, ply);
    // Stronger levels resolve mandatory captures before scoring a quiet leaf.
    // Beginner uses no extension so it can overlook the opponent's tactics.
    final extend = depth <= 0 && moves.first.isCapture && captureExtension > 0;
    if (depth <= 0 && !extend) return _evaluate();
    var best = -win * 2;
    var searched = 0;
    for (final move in moves) {
      session.applyMove(move);
      late int score;
      try {
        if (advanced && searched > 0) {
          score = -await _negamax(
            depth - 1,
            -alpha - 1,
            -alpha,
            ply + 1,
            extend ? captureExtension - 1 : captureExtension,
          );
          if (score > alpha && score < beta) {
            score = -await _negamax(
              depth - 1,
              -beta,
              -alpha,
              ply + 1,
              extend ? captureExtension - 1 : captureExtension,
            );
          }
        } else {
          score = -await _negamax(
            depth - 1,
            -beta,
            -alpha,
            ply + 1,
            extend ? captureExtension - 1 : captureExtension,
          );
        }
      } finally {
        session.undo();
      }
      if (score > best) best = score;
      if (score > alpha) alpha = score;
      searched++;
      if (alpha >= beta) {
        _cutoff(move, depth, ply);
        break;
      }
    }
    return best;
  }

  int _evaluate() {
    var value = 0;
    final size = session.position.size;
    for (var i = 0; i < session.position.pieces.length; i++) {
      final piece = session.position.pieces[i];
      if (piece == null) continue;
      final row = i ~/ size;
      final col = i % size;
      final advancement = piece.side == Side.black ? row : size - 1 - row;
      final centre = size - ((2 * col - size + 1).abs() ~/ 2);
      final material = piece.rank == DraughtsRank.king
          ? (session.rules.kingMove == KingMoveRule.short ? 240 : 320)
          : 100 + advancement * 4;
      value +=
          (piece.side == session.turn ? 1 : -1) *
          (material +
              centre * 2 +
              (advanced ? _positionValue(piece, row, col) : 0));
    }
    return value;
  }

  int _positionValue(DraughtsPiece piece, int row, int col) {
    final position = session.position, rules = session.rules;
    final size = position.size;
    final forward = rules.forward(piece.side);
    final king = piece.rank == DraughtsRank.king;
    final directions = rules.geometry == BoardGeometry.orthogonalAllSquares
        ? const [(1, 0), (-1, 0), (0, 1), (0, -1)]
        : const [(1, 1), (1, -1), (-1, 1), (-1, -1)];
    var support = 0, mobility = 0;
    for (final (dr, dc) in directions) {
      final next = Cell(row + dr, col + dc);
      if (!position.inside(next)) continue;
      if (position[next]?.side == piece.side) support++;
      if (!king &&
          dr != forward &&
          !(rules.manMove == ManMoveRule.forwardOrthogonalWithSideways &&
              dr == 0)) {
        continue;
      }
      final flying = king && rules.kingMove != KingMoveRule.short;
      for (var distance = 1; ; distance++) {
        final target = Cell(row + dr * distance, col + dc * distance);
        if (!position.inside(target) || position[target] != null) break;
        mobility++;
        if (!flying) break;
      }
    }
    var value = min(mobility, 12) * 2 + support * 3;
    if (!king) {
      final advance = piece.side == Side.black ? row : size - 1 - row;
      value += advance * advance * 2 ~/ size;
      if (advance == 0) value += 6;
    } else {
      // In a material advantage, bring kings towards the remaining opponents
      // instead of shuffling centrally until the draw counter expires.
      var own = 0, enemy = 0, distance = size;
      for (var i = 0; i < position.pieces.length; i++) {
        final other = position.pieces[i];
        if (other == null) continue;
        final weight = other.rank == DraughtsRank.king ? 3 : 1;
        if (other.side == piece.side) {
          own += weight;
        } else {
          enemy += weight;
          final dr = (row - i ~/ size).abs(), dc = (col - i % size).abs();
          distance = min(
            distance,
            rules.geometry == BoardGeometry.orthogonalAllSquares
                ? dr + dc
                : max(dr, dc),
          );
        }
      }
      if (own > enemy) value += (size - distance) * 3;
    }
    return value;
  }
}
