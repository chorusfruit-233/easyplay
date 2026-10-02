import 'dart:math';

import '../game_session.dart' show Side;
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
      captureExtension: level == DraughtsAiLevel.beginner ? 0 : 6,
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
  });

  final DraughtsSession session;
  final bool Function() cancelled;
  final int maxNodes;
  final int maxDepth;
  final Duration timeLimit;
  final int captureExtension;
  final Stopwatch clock = Stopwatch();
  int nodes = 0;
  static const win = 100000;

  Future<void> _visit() async {
    if (nodes % 16 == 0) await Future<void>.delayed(Duration.zero);
    if (cancelled() || nodes >= maxNodes || clock.elapsed >= timeLimit) {
      throw _SearchStopped();
    }
    nodes++;
  }

  List<DraughtsMove> _ordered([DraughtsMove? preferred]) {
    final moves = List<DraughtsMove>.of(session.legalMoves());
    int priority(DraughtsMove m) =>
        (m == preferred ? 10000 : 0) +
        m.captures.length * 100 +
        (session.rules.isPromotionCell(session.turn, m.to) ? 30 : 0);
    moves.sort((a, b) => priority(b).compareTo(priority(a)));
    return moves;
  }

  Future<DraughtsAiResult> run() async {
    clock.start();
    var best = _ordered().first;
    var completedDepth = 0;
    for (var depth = 1; depth <= maxDepth; depth++) {
      var score = -win * 2;
      var candidate = best;
      try {
        for (final move in _ordered(best)) {
          await _visit();
          session.applyMove(move);
          late final int value;
          try {
            value = -await _negamax(
              depth - 1,
              -win * 2,
              -score,
              1,
              captureExtension,
            );
          } finally {
            session.undo();
          }
          if (value > score) {
            score = value;
            candidate = move;
          }
        }
      } on _SearchStopped {
        break;
      }
      best = candidate;
      completedDepth = depth;
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
    final moves = _ordered();
    // Stronger levels resolve mandatory captures before scoring a quiet leaf.
    // Beginner uses no extension so it can overlook the opponent's tactics.
    final extend = depth <= 0 && moves.first.isCapture && captureExtension > 0;
    if (depth <= 0 && !extend) return _evaluate();
    var best = -win * 2;
    for (final move in moves) {
      session.applyMove(move);
      late final int score;
      try {
        score = -await _negamax(
          depth - 1,
          -beta,
          -alpha,
          ply + 1,
          extend ? captureExtension - 1 : captureExtension,
        );
      } finally {
        session.undo();
      }
      if (score > best) best = score;
      if (score > alpha) alpha = score;
      if (alpha >= beta) break;
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
      value += (piece.side == session.turn ? 1 : -1) * (material + centre * 2);
    }
    return value;
  }
}
