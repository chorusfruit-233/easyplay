import 'dart:math';
import '../doudizhu_model.dart';

/// Card counting from the player view only. Unplayed bottom cards are known
/// to belong to the landlord; everything else is an unknown allocation.
class PublicCards {
  PublicCards(this.view) {
    final excluded = {...view.hand, ...view.publicState.played};
    if (view.seat != view.publicState.landlord) {
      landlordCards = view.publicState.bottom
          .where((id) => !excluded.contains(id))
          .toList();
      excluded.addAll(landlordCards);
    }
    unknown = [
      for (var id = 0; id < 54; id++)
        if (!excluded.contains(id)) id,
    ];
    for (final id in unknown) {
      _ranks[PlayingCard(id).rank]++;
    }
  }
  final DouDizhuPlayerView view;
  late final List<int> unknown;
  List<int> landlordCards = [];
  final _ranks = List.filled(18, 0);
  final _cache = <String, double>{};

  List<int> known(PlayerSeat seat) =>
      seat == view.publicState.landlord ? landlordCards : const [];
  int _draws(PlayerSeat seat) =>
      max(0, view.publicState.counts[seat.index] - known(seat).length);

  double _hasRank(PlayerSeat seat, int rank, int number) {
    final fixed = known(
      seat,
    ).where((id) => PlayingCard(id).rank == rank).length;
    final need = number - fixed;
    if (need <= 0) return 1;
    final available = _ranks[rank], draws = _draws(seat), pool = unknown.length;
    if (available < need || draws < need || pool == 0) return 0;
    var probability = 0.0;
    for (var n = need; n <= min(available, draws); n++) {
      probability +=
          _combination(available, n) *
          _combination(pool - available, draws - n) /
          _combination(pool, draws);
    }
    return probability.clamp(0, 1);
  }

  double _rocket(PlayerSeat seat) {
    final fixed = known(seat).map((id) => PlayingCard(id).rank).toSet();
    final missing = [16, 17].where((r) => !fixed.contains(r)).toList();
    if (missing.any((r) => _ranks[r] == 0)) return 0;
    var value = 1.0;
    for (var i = 0; i < missing.length; i++) {
      if (_draws(seat) <= i || unknown.length <= i) return 0;
      value *= (_draws(seat) - i) / (unknown.length - i);
    }
    return value;
  }

  /// Hypergeometric rank probabilities; unions and sequence bodies use a
  /// conservative approximation, not knowledge of an opponent's actual hand.
  double chanceToBeat(PlayerSeat seat, PlayPattern pattern) {
    final key =
        '${seat.index}:${pattern.type.index}:${pattern.mainRank}:${pattern.totalCards}:${pattern.sequenceLength}';
    return _cache.putIfAbsent(key, () {
      final count = view.publicState.counts[seat.index];
      if (count == 0 || pattern.type == PlayType.rocket) return 0;
      var probability = 0.0;
      if (count >= pattern.totalCards) {
        final each = switch (pattern.type) {
          PlayType.pair || PlayType.pairStraight => 2,
          PlayType.triple ||
          PlayType.tripleSingle ||
          PlayType.triplePair ||
          PlayType.airplane ||
          PlayType.airplaneSingles ||
          PlayType.airplanePairs => 3,
          PlayType.fourSingles || PlayType.fourPairs || PlayType.bomb => 4,
          _ => 1,
        };
        final sequence = pattern.sequenceLength;
        final maxRank = sequence > 1
            ? 14
            : each == 1
            ? 17
            : 15;
        for (var end = pattern.mainRank + 1; end <= maxRank; end++) {
          var p = 1.0;
          for (var rank = end - sequence + 1; rank <= end; rank++) {
            p *= _hasRank(seat, rank, each);
          }
          probability += p;
        }
      }
      if (count >= 4 && pattern.type != PlayType.bomb) {
        for (var rank = 3; rank <= 15; rank++) {
          probability += _hasRank(seat, rank, 4);
        }
      }
      if (count >= 2) probability += _rocket(seat);
      return probability.clamp(0, 1);
    });
  }

  /// Uniform possible hands respecting known bottom cards and public counts.
  List<List<int>>? sample(Random random) {
    final seats = PlayerSeat.values.where((s) => s != view.seat).toList();
    final draws = seats.map(_draws).toList();
    if (draws.fold<int>(0, (a, b) => a + b) != unknown.length) return null;
    final pool = List<int>.of(unknown)..shuffle(random);
    final hands = List.generate(3, (_) => <int>[]);
    hands[view.seat.index] = List<int>.of(view.hand);
    var offset = 0;
    for (var i = 0; i < seats.length; i++) {
      hands[seats[i].index] = [
        ...known(seats[i]),
        ...pool.sublist(offset, offset + draws[i]),
      ];
      offset += draws[i];
    }
    return hands;
  }
}

double _combination(int n, int k) {
  if (k < 0 || k > n) return 0;
  k = min(k, n - k);
  var value = 1.0;
  for (var i = 1; i <= k; i++) {
    value = value * (n - k + i) / i;
  }
  return value;
}
