import 'dart:math';
import '../doudizhu_model.dart';
import 'legal_play_generator.dart';

/// Bounded rank-based partition search, shared by all candidates in one turn.
/// A partition can contain straights, airplanes and attachments, not just ranks.
class HandPlan {
  HandPlan(List<int> hand, {this.nodeBudget = 1800}) {
    final counts = rankCounts(hand);
    final plays = const LegalPlayGenerator().generate(
      hand.map(PlayingCard.new).toList(),
      const TrickState(),
    );
    for (final ids in plays) {
      final shape = rankCounts(ids);
      final move = _Shape(shape, ids.length);
      for (var rank = 0; rank < shape.length; rank++) {
        if (shape[rank] > 0) _byRank[rank].add(move);
      }
    }
    for (final shapes in _byRank) {
      shapes.sort((a, b) => b.size.compareTo(a.size));
    }
    initialTurns = turnsForCounts(counts);
  }
  final int nodeBudget;
  final _byRank = List.generate(15, (_) => <_Shape>[]);
  final _memo = <int, int>{0: 0};
  int _nodes = 0;
  late final int initialTurns;

  int turns(Iterable<int> hand) => turnsForCounts(rankCounts(hand));

  int turnsForCounts(List<int> counts) {
    final key = _key(counts);
    final cached = _memo[key];
    if (cached != null) return cached;
    if (++_nodes > nodeBudget) return greedyTurns(counts);
    final rank = counts.indexWhere((n) => n > 0);
    final total = counts.fold<int>(0, (a, b) => a + b);
    var best = total;
    for (final move in _byRank[rank]) {
      if (move.size > total || !_fits(move.counts, counts)) continue;
      if (move.size == total) return _memo[key] = 1;
      final rest = List<int>.generate(15, (i) => counts[i] - move.counts[i]);
      best = min(best, 1 + turnsForCounts(rest));
      if (best == 2) break;
    }
    return _memo[key] = best;
  }

  static bool _fits(List<int> shape, List<int> counts) {
    for (var i = 0; i < 15; i++) {
      if (shape[i] > counts[i]) return false;
    }
    return true;
  }

  // Arithmetic radix encoding also works on Web, unlike a 54-bit card mask.
  static int _key(List<int> counts) {
    var key = 0;
    for (final count in counts) {
      key = key * 5 + count;
    }
    return key;
  }
}

List<int> rankCounts(Iterable<int> cards) {
  final counts = List.filled(15, 0);
  for (final id in cards) {
    counts[PlayingCard(id).rank - 3]++;
  }
  return counts;
}

/// Cheap fallback once the partition budget has been spent.
int greedyTurns(List<int> input) {
  final counts = List<int>.of(input);
  var turns = 0;
  if (counts[13] > 0 && counts[14] > 0) {
    counts[13]--;
    counts[14]--;
    turns++;
  }
  for (final (each, minimum) in [(3, 2), (2, 3), (1, 5)]) {
    for (var start = 0; start < 12; start++) {
      if (counts[start] < each) continue;
      var end = start;
      while (end < 12 && counts[end] >= each) {
        end++;
      }
      if (end - start < minimum) continue;
      for (var i = start; i < end; i++) {
        counts[i] -= each;
      }
      turns++;
      start--;
    }
  }
  // Attach low singles/pairs to triples without consuming control cards.
  for (var rank = 0; rank < 13; rank++) {
    if (counts[rank] != 3) continue;
    counts[rank] = 0;
    var wing = counts.indexWhere((n) => n == 1);
    if (wing < 0) wing = counts.indexWhere((n) => n == 2);
    if (wing >= 0 && wing < 12) counts[wing] = 0;
    turns++;
  }
  return turns + counts.where((n) => n > 0).length;
}

class _Shape {
  const _Shape(this.counts, this.size);
  final List<int> counts;
  final int size;
}
