// Frozen v1.6.1 policy for reproducible strength comparisons.
import 'package:flutter/foundation.dart';
import 'package:easyplay/doudizhu/doudizhu_model.dart';
import 'package:easyplay/doudizhu/doudizhu_rules.dart';
import 'package:easyplay/doudizhu/ai/legal_play_generator.dart';

class BiddingPolicy {
  const BiddingPolicy();
  int choose(DouDizhuPlayerView view) {
    final ranks = <int, int>{};
    for (final id in view.hand) {
      ranks.update(PlayingCard(id).rank, (n) => n + 1, ifAbsent: () => 1);
    }
    var strength = view.hand.where((id) => PlayingCard(id).rank >= 15).length;
    strength += ranks.values.where((n) => n == 4).length * 3;
    if (ranks.containsKey(16) && ranks.containsKey(17)) strength += 3;
    final score = strength >= 7
        ? 3
        : strength >= 5
        ? 2
        : strength >= 3
        ? 1
        : 0;
    return score > view.publicState.highestBid ? score : 0;
  }
}

class TeamPolicy {
  const TeamPolicy();
  bool shouldYield(DouDizhuPlayerView view) =>
      view.publicState.landlord != view.seat &&
      view.publicState.trick.seat != null &&
      view.publicState.trick.seat != view.publicState.landlord &&
      view.publicState.counts[view.publicState.trick.seat!.index] <= 2;
}

class HandEvaluator {
  const HandEvaluator();
  double cost(Iterable<int> hand) {
    final groups = <int, int>{};
    for (final id in hand) {
      groups.update(PlayingCard(id).rank, (n) => n + 1, ifAbsent: () => 1);
    }
    return groups.values.fold(
      0.0,
      (cost, n) =>
          cost +
          (n == 1
              ? 1.5
              : n == 2
              ? 1
              : .6),
    );
  }
}

class PlayEvaluator {
  const PlayEvaluator();
  double score(DouDizhuPlayerView view, List<int> ids) {
    final p = classifyPlay(ids.map(PlayingCard.new).toList())!;
    final urgent = PlayerSeat.values.any(
      (s) =>
          s != view.seat &&
          (s == view.publicState.landlord ||
              view.seat == view.publicState.landlord) &&
          view.publicState.counts[s.index] <= 2,
    );
    return const HandEvaluator().cost(
              view.hand.where((id) => !ids.contains(id)),
            ) *
            5 +
        p.mainRank * (urgent ? -.25 : .15) +
        (p.type == PlayType.bomb || p.type == PlayType.rocket ? 8 : 0) -
        ids.length;
  }
}

class LegacyDouDizhuAi {
  const LegacyDouDizhuAi();
  static const candidateBudget = 4096;
  List<List<int>> _options(DouDizhuPlayerView view) =>
      const LegalPlayGenerator().generate(
        view.hand.map(PlayingCard.new).toList(),
        view.publicState.trick,
      );
  List<int>? _immediate(DouDizhuPlayerView view, List<List<int>> options) {
    if (options.isEmpty) return [];
    for (final option in options) {
      if (option.length == view.hand.length) return option;
    }
    if (const TeamPolicy().shouldYield(view)) return [];
    return null;
  }

  List<int> choosePlay(DouDizhuPlayerView view) {
    final options = _options(view);
    final immediate = _immediate(view, options);
    if (immediate != null) return immediate;
    List<int> best = options.first;
    var score = double.infinity;
    for (final option in options.take(candidateBudget)) {
      final value = const PlayEvaluator().score(view, option);
      if (value < score) {
        score = value;
        best = option;
      }
    }
    return best;
  }

  Future<List<int>> chooseAsync(DouDizhuPlayerView view) async {
    if (!kIsWeb) return compute(_choose, view.toWire());
    // Web compute() uses the UI thread. Yield between bounded batches instead.
    final options = _options(view);
    final immediate = _immediate(view, options);
    if (immediate != null) return immediate;
    List<int> best = options.first;
    var score = double.infinity, count = 0;
    for (final option in options.take(candidateBudget)) {
      final value = const PlayEvaluator().score(view, option);
      if (value < score) {
        score = value;
        best = option;
      }
      if (++count % 32 == 0) await Future<void>.delayed(Duration.zero);
    }
    return best;
  }
}

List<int> _choose(Map<String, Object?> wire) =>
    const LegacyDouDizhuAi().choosePlay(DouDizhuPlayerView.fromWire(wire));
