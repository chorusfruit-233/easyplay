import 'doudizhu_model.dart';

/// A player's most recent cards and pass status within one public trick.
class DouDizhuSeatPlay {
  DouDizhuSeatPlay(Iterable<int> cards, {this.passed = false})
    : cards = List.unmodifiable(cards);

  final List<int> cards;
  final bool passed;
}

/// Derived solely from public snapshots, so reconnecting restores the table.
/// Keep a completed trick visible until the next actual lead replaces it.
class DouDizhuTableRound {
  DouDizhuTableRound._(this.plays, this.topSeat, this.complete);

  final Map<PlayerSeat, DouDizhuSeatPlay> plays;
  final PlayerSeat? topSeat;
  final bool complete;

  factory DouDizhuTableRound.fromState(PublicGameState state) {
    final plays = <PlayerSeat, DouDizhuSeatPlay>{};
    PlayerSeat? top;
    var passes = 0;
    var complete = false;
    if (state.phase != DouDizhuPhase.playing &&
        state.phase != DouDizhuPhase.finished) {
      return DouDizhuTableRound._(const {}, null, false);
    }
    final history = state.history;
    if (history == null) {
      // Older hosts expose only the current highest play.
      if (state.trick.seat case final seat?) {
        plays[seat] = DouDizhuSeatPlay(state.trick.cardIds);
        top = seat;
      }
    } else {
      for (final action in history) {
        if (action.cardIds.isNotEmpty) {
          if (complete) plays.clear();
          plays[action.seat] = DouDizhuSeatPlay(action.cardIds);
          top = action.seat;
          passes = 0;
          complete = false;
        } else {
          plays[action.seat] = DouDizhuSeatPlay(
            plays[action.seat]?.cards ?? const [],
            passed: true,
          );
          complete = ++passes >= 2;
        }
      }
    }
    return DouDizhuTableRound._(Map.unmodifiable(plays), top, complete);
  }
}
