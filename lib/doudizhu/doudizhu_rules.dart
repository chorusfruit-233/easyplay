import 'doudizhu_model.dart';

const doudizhuRulesVersion = 1;

/// Fixed profile: airplane single wings have distinct ranks, may contain one
/// joker, and never contain body ranks. Four-with-two singles may be a pair,
/// but cannot be both jokers. Pair wings are distinct non-body ranks.
class DouDizhuRules {
  const DouDizhuRules();
  PlayPattern? classifyPlay(List<PlayingCard> cards) {
    if (cards.isEmpty ||
        cards.length > 20 ||
        cards.map((c) => c.id).toSet().length != cards.length) {
      return null;
    }
    final groups = <int, int>{};
    for (final card in cards) {
      groups.update(card.rank, (n) => n + 1, ifAbsent: () => 1);
    }
    final ranks = groups.keys.toList()..sort();
    final n = cards.length;
    PlayPattern p(PlayType t, int rank, [int length = 1]) =>
        PlayPattern(t, rank, length, n);
    if (n == 2 && groups.containsKey(16) && groups.containsKey(17)) {
      return p(PlayType.rocket, 17);
    }
    if (ranks.length == 1) {
      return switch (n) {
        1 => p(PlayType.single, ranks.single),
        2 => p(PlayType.pair, ranks.single),
        3 => p(PlayType.triple, ranks.single),
        4 => p(PlayType.bomb, ranks.single),
        _ => null,
      };
    }
    bool consecutive(List<int> rs) =>
        rs.last <= 14 && rs.last - rs.first + 1 == rs.length;
    if (n >= 5 && ranks.length == n && consecutive(ranks)) {
      return p(PlayType.straight, ranks.last, n);
    }
    if (n >= 6 &&
        n.isEven &&
        groups.values.every((v) => v == 2) &&
        consecutive(ranks)) {
      return p(PlayType.pairStraight, ranks.last, ranks.length);
    }
    if (n >= 6 &&
        n % 3 == 0 &&
        groups.values.every((v) => v == 3) &&
        consecutive(ranks)) {
      return p(PlayType.airplane, ranks.last, ranks.length);
    }
    for (final rank in ranks.reversed) {
      if (groups[rank] == 3) {
        if (n == 4) return p(PlayType.tripleSingle, rank);
        if (n == 5 && groups.values.contains(2)) {
          return p(PlayType.triplePair, rank);
        }
      }
      if (groups[rank] == 4) {
        final rest = Map<int, int>.of(groups)..remove(rank);
        if (n == 6 && !(rest.containsKey(16) && rest.containsKey(17))) {
          return p(PlayType.fourSingles, rank);
        }
        if (n == 8 && rest.length == 2 && rest.values.every((v) => v == 2)) {
          return p(PlayType.fourPairs, rank);
        }
      }
    }
    // Enumerate every possible body, including ambiguous triple runs.
    for (final wings in [1, 2]) {
      final unit = 3 + wings;
      if (n % unit != 0 || n ~/ unit < 2) continue;
      final length = n ~/ unit;
      for (var end = 14; end >= 3 + length - 1; end--) {
        final body = [for (var r = end - length + 1; r <= end; r++) r];
        if (body.any((r) => groups[r] != 3)) continue;
        final rest = Map<int, int>.of(groups)
          ..removeWhere((r, _) => body.contains(r));
        if (rest.length == length &&
            rest.values.every((v) => v == wings) &&
            !(wings == 1 && rest.containsKey(16) && rest.containsKey(17))) {
          return p(
            wings == 1 ? PlayType.airplaneSingles : PlayType.airplanePairs,
            end,
            length,
          );
        }
      }
    }
    return null;
  }

  bool canBeat(PlayPattern candidate, PlayPattern previous) {
    if (previous.type == PlayType.rocket) return false;
    if (candidate.type == PlayType.rocket) return true;
    if (candidate.type == PlayType.bomb && previous.type != PlayType.bomb) {
      return true;
    }
    return candidate.type == previous.type &&
        candidate.totalCards == previous.totalCards &&
        candidate.sequenceLength == previous.sequenceLength &&
        candidate.mainRank > previous.mainRank;
  }
}

PlayPattern? classifyPlay(List<PlayingCard> cards) =>
    const DouDizhuRules().classifyPlay(cards);
bool canBeat(PlayPattern candidate, PlayPattern previous) =>
    const DouDizhuRules().canBeat(candidate, previous);
