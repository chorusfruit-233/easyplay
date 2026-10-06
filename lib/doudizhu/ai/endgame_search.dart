import 'dart:math';
import '../doudizhu_model.dart';
import 'hand_plan.dart';
import 'legal_play_generator.dart';

/// Team minimax within one sampled allocation. Samples come from public cards,
/// never from the authority. Search is a belief estimate, not a proven win.
class EndgameSearch {
  EndgameSearch({
    required this.landlord,
    required this.rootSeat,
    this.nodeBudget = 320,
  });
  final PlayerSeat landlord, rootSeat;
  final int nodeBudget;
  int _nodes = 0;

  double evaluate(List<List<int>> hands, TrickState trick, List<int> play) {
    final state = _after(hands, rootSeat, trick, play);
    return _search(state.$1, rootSeat.next, state.$2, 0, -1, 1);
  }

  double _search(
    List<List<int>> hands,
    PlayerSeat turn,
    TrickState trick,
    int depth,
    double alpha,
    double beta,
  ) {
    for (final seat in PlayerSeat.values) {
      if (hands[seat.index].isEmpty) return _sameTeam(seat, rootSeat) ? 1 : -1;
    }
    if (++_nodes > nodeBudget || depth >= 18) return _race(hands);
    final options = const LegalPlayGenerator().generate(
      hands[turn.index].map(PlayingCard.new).toList(),
      trick,
    )..sort((a, b) => b.length.compareTo(a.length));
    if (trick.seat != null && trick.seat != turn) options.add([]);
    final maximizing = _sameTeam(turn, rootSeat);
    var value = maximizing ? -1.0 : 1.0;
    for (final play in options) {
      final state = _after(hands, turn, trick, play);
      final score = _search(
        state.$1,
        turn.next,
        state.$2,
        depth + 1,
        alpha,
        beta,
      );
      if (maximizing) {
        value = max(value, score);
        alpha = max(alpha, value);
      } else {
        value = min(value, score);
        beta = min(beta, value);
      }
      if (alpha >= beta) break;
    }
    return value;
  }

  bool _sameTeam(PlayerSeat a, PlayerSeat b) =>
      (a == landlord) == (b == landlord);

  double _race(List<List<int>> hands) {
    final turns = hands.map((h) => greedyTurns(rankCounts(h))).toList();
    final farmers = PlayerSeat.values.where((s) => s != landlord);
    final farmerTurns = farmers.map((s) => turns[s.index]).reduce(min);
    final value =
        (farmerTurns - turns[landlord.index]) /
        (farmerTurns + turns[landlord.index] + 1);
    return rootSeat == landlord ? value : -value;
  }

  static (List<List<int>>, TrickState) _after(
    List<List<int>> hands,
    PlayerSeat seat,
    TrickState trick,
    List<int> play,
  ) {
    if (play.isEmpty) {
      return (
        hands,
        trick.passes == 1
            ? const TrickState()
            : TrickState(seat: trick.seat, cardIds: trick.cardIds, passes: 1),
      );
    }
    final next = List<List<int>>.of(hands);
    next[seat.index] = hands[seat.index]
        .where((id) => !play.contains(id))
        .toList();
    return (next, TrickState(seat: seat, cardIds: play));
  }
}
