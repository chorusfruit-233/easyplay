import 'dart:math';
import 'package:flutter/foundation.dart';
import '../doudizhu_model.dart';
import '../doudizhu_rules.dart';
import 'endgame_search.dart';
import 'hand_plan.dart';
import 'legal_play_generator.dart';
import 'public_cards.dart';

class BiddingPolicy {
  const BiddingPolicy();
  int choose(DouDizhuPlayerView view) {
    final counts = rankCounts(view.hand);
    var control = counts[12] * 1.2 + counts[13] * 1.6 + counts[14] * 2;
    control += counts.take(13).where((n) => n == 4).length * 2.5;
    if (counts[13] == 1 && counts[14] == 1) control += 2;
    control += counts[11] >= 2 ? 1.0 : counts[11] * .3;
    final turns = HandPlan(view.hand, nodeBudget: 600).initialTurns;
    final strength = control + max(0, 6 - turns) * .9 - max(0, turns - 7) * .7;
    final score = strength >= 7.5 && turns <= 7
        ? 3
        : strength >= 5
        ? 2
        : strength >= 2.5
        ? 1
        : 0;
    return score > view.publicState.highestBid ? score : 0;
  }
}

class TeamPolicy {
  const TeamPolicy();
  bool shouldYield(DouDizhuPlayerView view) {
    final state = view.publicState;
    if (state.landlord == null ||
        state.landlord == view.seat ||
        state.trick.seat == null ||
        state.trick.seat == state.landlord ||
        state.trick.seat == view.seat) {
      return false;
    }
    final landlord = state.landlord!;
    // Let a teammate close to finishing retain the lead. Intercept when the
    // landlord is next and may finish over the teammate's current play.
    if (view.seat.next == landlord && state.counts[landlord.index] <= 2) {
      final pattern = classifyPlay(
        state.trick.cardIds.map(PlayingCard.new).toList(),
      );
      if (pattern != null &&
          PublicCards(view).chanceToBeat(landlord, pattern) > .15) {
        return false;
      }
    }
    return state.counts[state.trick.seat!.index] <= 2;
  }
}

class DouDizhuAi {
  const DouDizhuAi();
  static const candidateBudget = 4096;

  List<int> choosePlay(DouDizhuPlayerView view) {
    final decision = _Decision(view);
    for (final _ in decision.run()) {
      /* Advance bounded search. */
    }
    return decision.best;
  }

  Future<List<int>> chooseAsync(DouDizhuPlayerView view) async {
    if (!kIsWeb) return compute(_choose, view.toWire());
    final decision = _Decision(view);
    var count = 0;
    for (final step in decision.run()) {
      if (step < 0 || ++count % 12 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return decision.best;
  }
}

class _Candidate {
  _Candidate(this.cards, this.score);
  final List<int> cards;
  final double score;
}

class _Decision {
  _Decision(this.view);
  final DouDizhuPlayerView view;
  List<int> best = [];

  Iterable<int> run() sync* {
    if (view.publicState.phase != DouDizhuPhase.playing || view.hand.isEmpty) {
      return;
    }
    final options = const LegalPlayGenerator().generate(
      view.hand.map(PlayingCard.new).toList(),
      view.publicState.trick,
    );
    if (options.isEmpty) return;
    for (final option in options) {
      if (option.length == view.hand.length) {
        best = option;
        return;
      }
    }
    if (const TeamPolicy().shouldYield(view)) return;
    final plan = HandPlan(view.hand);
    final publicCards = PublicCards(view);
    final enemies = PlayerSeat.values
        .where(
          (s) =>
              s != view.seat &&
              (view.seat == view.publicState.landlord ||
                  s == view.publicState.landlord),
        )
        .toList();
    final urgent = enemies.any((s) => view.publicState.counts[s.index] <= 2);
    final ownCounts = rankCounts(view.hand);
    final candidates = <_Candidate>[];
    var tick = 0;
    for (final ids in options.take(DouDizhuAi.candidateBudget)) {
      final pattern = classifyPlay(ids.map(PlayingCard.new).toList())!;
      final used = rankCounts(ids);
      final rest = List<int>.generate(15, (i) => ownCounts[i] - used[i]);
      var score =
          plan.turnsForCounts(rest) * 2 + _fragmentation(rest) * 5 - ids.length;
      score += pattern.mainRank * (urgent ? -.25 : .15);
      if (pattern.type == PlayType.bomb || pattern.type == PlayType.rocket) {
        score += 8;
      }
      if (view.publicState.trick.seat == null &&
          view.seat != view.publicState.landlord &&
          view.seat.next != view.publicState.landlord &&
          !urgent) {
        final partnerCount = view.publicState.counts[view.seat.next.index];
        if (partnerCount == 1 && pattern.type == PlayType.single) {
          score -= publicCards.chanceToBeat(view.seat.next, pattern) * 65;
        }
        if (partnerCount == 2 && pattern.type == PlayType.pair) {
          score -= publicCards.chanceToBeat(view.seat.next, pattern) * 24;
        }
      }
      candidates.add(_Candidate(ids, score));
      yield ++tick;
    }
    if (view.publicState.trick.seat != null) {
      // Passing is an actual alternative to breaking a combination or wasting
      // a bomb, but carries a large penalty when an enemy may go out next.
      candidates.add(
        _Candidate(
          [],
          _fragmentation(ownCounts) * 5 +
              plan.initialTurns * 2 -
              3 +
              (urgent ? 55 : 0) -
              (view.publicState.trick.seat != view.publicState.landlord &&
                      view.seat != view.publicState.landlord
                  ? 5
                  : 0),
        ),
      );
    }
    candidates.sort(_compare);
    best = candidates.first.cards;
    // Once few cards remain, test promising actions against several possible
    // hidden allocations and search both farmers as a single team.
    if (view.publicState.counts.fold<int>(0, (a, b) => a + b) > 10 ||
        view.publicState.landlord == null) {
      return;
    }
    final finalists = candidates.take(8).toList();
    final random = Random(_seed(view));
    final totals = List.filled(finalists.length, 0.0);
    var worlds = 0;
    for (var sample = 0; sample < 12; sample++) {
      final hands = publicCards.sample(random);
      if (hands == null) break;
      worlds++;
      for (var i = 0; i < finalists.length; i++) {
        totals[i] += EndgameSearch(
          landlord: view.publicState.landlord!,
          rootSeat: view.seat,
          nodeBudget: 1600,
        ).evaluate(hands, view.publicState.trick, finalists[i].cards);
        // Yield after each bounded tactical search on Web.
        yield -(++tick);
      }
    }
    if (worlds == 0) return;
    var bestValue = double.negativeInfinity;
    for (var i = 0; i < finalists.length; i++) {
      final value = totals[i] / worlds - finalists[i].score * .002;
      if (value > bestValue) {
        bestValue = value;
        best = finalists[i].cards;
      }
    }
  }

  static int _compare(_Candidate a, _Candidate b) {
    final score = a.score.compareTo(b.score);
    if (score != 0) return score;
    final length = b.cards.length.compareTo(a.cards.length);
    if (length != 0) return length;
    for (var i = 0; i < a.cards.length; i++) {
      final rank = PlayingCard(
        a.cards[i],
      ).rank.compareTo(PlayingCard(b.cards[i]).rank);
      if (rank != 0) return rank;
    }
    return 0;
  }

  static int _seed(DouDizhuPlayerView view) {
    final sorted = [...view.hand, ...view.publicState.played]..sort();
    var seed = view.seat.index + 1;
    for (final id in sorted) {
      seed = (seed * 31 + id) & 0x7fffffff;
    }
    for (final count in view.publicState.counts) {
      seed = (seed * 31 + count) & 0x7fffffff;
    }
    return seed;
  }
}

double _fragmentation(List<int> counts) => counts.fold<double>(
  0,
  (sum, n) =>
      sum +
      (n == 0
          ? 0
          : n == 1
          ? 1.5
          : n == 2
          ? 1
          : .6),
);

List<int> _choose(Map<String, Object?> wire) =>
    const DouDizhuAi().choosePlay(DouDizhuPlayerView.fromWire(wire));
