import 'dart:math';

enum PlayerSeat {
  seat0,
  seat1,
  seat2;

  PlayerSeat get next => values[(index + 1) % 3];
  String get label => '玩家 ${index + 1}';
}

enum DouDizhuPhase { waiting, dealing, bidding, playing, finished }

enum DouDizhuTeam { landlord, farmers }

enum CardSuit { spade, heart, club, diamond, joker }

/// Ranks 3..14 (ace), 15 (two), 16/17 (small/big joker).
class PlayingCard {
  PlayingCard(this.id) {
    if (id < 0 || id > 53) throw ArgumentError.value(id, 'id');
  }
  final int id;
  int get rank => id < 52 ? 3 + id ~/ 4 : id - 36;
  CardSuit get suit => id < 52 ? CardSuit.values[id % 4] : CardSuit.joker;
  String get label => switch (rank) {
    11 => 'J',
    12 => 'Q',
    13 => 'K',
    14 => 'A',
    15 => '2',
    16 => '小王',
    17 => '大王',
    _ => '$rank',
  };
  String get symbol => switch (suit) {
    CardSuit.spade => '♠',
    CardSuit.heart => '♥',
    CardSuit.club => '♣',
    CardSuit.diamond => '♦',
    CardSuit.joker => '★',
  };
  bool get red =>
      suit == CardSuit.heart || suit == CardSuit.diamond || id == 53;
  static List<PlayingCard> deck({Random? random}) =>
      List.generate(54, PlayingCard.new)..shuffle(random ?? Random.secure());
  static List<PlayingCard> sorted(Iterable<PlayingCard> cards) =>
      cards.toList()..sort((a, b) => b.id.compareTo(a.id));
}

class CardPlay {
  CardPlay(this.seat, Iterable<int> cardIds)
    : cardIds = List.unmodifiable(cardIds);
  final PlayerSeat seat;
  final List<int> cardIds;
}

enum PlayType {
  single,
  pair,
  triple,
  tripleSingle,
  triplePair,
  straight,
  pairStraight,
  airplane,
  airplaneSingles,
  airplanePairs,
  fourSingles,
  fourPairs,
  bomb,
  rocket;

  String get label => switch (this) {
    single => '单牌',
    pair => '对子',
    triple => '三张',
    tripleSingle => '三带一',
    triplePair => '三带二',
    straight => '顺子',
    pairStraight => '连对',
    airplane => '飞机',
    airplaneSingles => '飞机带单',
    airplanePairs => '飞机带对',
    fourSingles => '四带二',
    fourPairs => '四带两对',
    bomb => '炸弹',
    rocket => '王炸',
  };
}

class PlayPattern {
  const PlayPattern(
    this.type,
    this.mainRank,
    this.sequenceLength,
    this.totalCards,
  );
  final PlayType type;
  final int mainRank, sequenceLength, totalCards;
}

class TrickState {
  const TrickState({this.seat, this.cardIds = const [], this.passes = 0});
  final PlayerSeat? seat;
  final List<int> cardIds;
  final int passes;
}

class PublicGameState {
  PublicGameState({
    required this.phase,
    required this.turn,
    required this.counts,
    required this.bids,
    required this.bottom,
    required this.played,
    required this.trick,
    this.landlord,
    this.winner,
    this.winningSeat,
    this.dealNumber = 0,
  });
  final DouDizhuPhase phase;
  final PlayerSeat turn;
  final PlayerSeat? landlord, winningSeat;
  final DouDizhuTeam? winner;
  final List<int> counts, bottom, played;
  final List<int?> bids;
  final TrickState trick;
  final int dealNumber;
  int get highestBid => bids.whereType<int>().fold(0, max);
  Map<String, Object?> toWire() => {
    'phase': phase.name,
    'turn': turn.index,
    'counts': counts,
    'bids': bids,
    'bottom': bottom,
    'played': played,
    'landlord': landlord?.index,
    'winner': winner?.name,
    'winningSeat': winningSeat?.index,
    'dealNumber': dealNumber,
    'trick': {
      'seat': trick.seat?.index,
      'cards': trick.cardIds,
      'passes': trick.passes,
    },
  };
  factory PublicGameState.fromWire(Map<String, Object?> d) {
    int number(Object? value, int max) {
      if (value is! int || value < 0 || value > max) {
        throw const FormatException('无效的公共状态数字');
      }
      return value;
    }

    PlayerSeat? seat(Object? value) =>
        value == null ? null : PlayerSeat.values[number(value, 2)];
    List<int> cards(Object? value) {
      if (value is! List ||
          value.length > 54 ||
          value.toSet().length != value.length) {
        throw const FormatException('无效或重复的公共牌');
      }
      return List.unmodifiable(value.map((v) => number(v, 53)));
    }

    final rawCounts = d['counts'], rawBids = d['bids'], rawTrick = d['trick'];
    if (rawCounts is! List ||
        rawCounts.length != 3 ||
        rawBids is! List ||
        rawBids.length != 3 ||
        rawTrick is! Map) {
      throw const FormatException('无效的公共状态');
    }
    final phase = DouDizhuPhase.values
        .where((p) => p.name == d['phase'])
        .firstOrNull;
    final winner = DouDizhuTeam.values
        .where((p) => p.name == d['winner'])
        .firstOrNull;
    if (phase == null ||
        d['winner'] != null && winner == null ||
        d['turn'] == null) {
      throw const FormatException('无效阶段或结果');
    }
    final state = PublicGameState(
      phase: phase,
      turn: seat(d['turn'])!,
      counts: List.unmodifiable(rawCounts.map((v) => number(v, 20))),
      bids: List.unmodifiable(
        rawBids.map((v) => v == null ? null : number(v, 3)),
      ),
      bottom: cards(d['bottom']),
      played: cards(d['played']),
      trick: TrickState(
        seat: seat(rawTrick['seat']),
        cardIds: cards(rawTrick['cards']),
        passes: number(rawTrick['passes'], 1),
      ),
      landlord: seat(d['landlord']),
      winner: winner,
      winningSeat: seat(d['winningSeat']),
      dealNumber: number(d['dealNumber'], 1000000000),
    );
    final t = state.trick;
    if (state.bottom.length > 3 ||
        t.cardIds.any((id) => !state.played.contains(id)) ||
        (t.seat == null) != (t.cardIds.isEmpty) ||
        t.seat == null && t.passes != 0 ||
        state.landlord != null && state.bottom.length != 3) {
      throw const FormatException('公共牌桌状态不一致');
    }
    if ([DouDizhuPhase.waiting, DouDizhuPhase.bidding].contains(phase)) {
      if (state.landlord != null ||
          state.bottom.isNotEmpty ||
          state.played.isNotEmpty ||
          winner != null ||
          state.winningSeat != null ||
          t.cardIds.isNotEmpty ||
          state.counts.any(
            (n) => n != (phase == DouDizhuPhase.waiting ? 0 : 17),
          )) {
        throw const FormatException('发牌阶段状态不一致');
      }
    } else if (phase == DouDizhuPhase.playing ||
        phase == DouDizhuPhase.finished) {
      if (state.landlord == null ||
          state.counts.fold<int>(0, (a, b) => a + b) + state.played.length !=
              54 ||
          PlayerSeat.values.any(
            (s) => state.counts[s.index] > (s == state.landlord ? 20 : 17),
          )) {
        throw const FormatException('公共牌数不守恒');
      }
      if (phase == DouDizhuPhase.finished) {
        if (winner == null ||
            state.winningSeat == null ||
            state.counts[state.winningSeat!.index] != 0 ||
            winner !=
                (state.winningSeat == state.landlord
                    ? DouDizhuTeam.landlord
                    : DouDizhuTeam.farmers)) {
          throw const FormatException('无效胜负结果');
        }
      } else if (winner != null || state.winningSeat != null) {
        throw const FormatException('未结束的对局不能有结果');
      }
    }
    return state;
  }
}

/// The only input supplied to clients and AI. No reference to the authority.
class DouDizhuPlayerView {
  DouDizhuPlayerView({
    required this.seat,
    required this.publicState,
    required Iterable<int> hand,
  }) : hand = List.unmodifiable(hand);
  final PlayerSeat seat;
  final PublicGameState publicState;
  final List<int> hand;
  bool get isTurn => publicState.turn == seat;
  Map<String, Object?> toWire() => {
    'seat': seat.index,
    'public': publicState.toWire(),
    'hand': hand,
  };
  factory DouDizhuPlayerView.fromWire(Map<String, Object?> d) {
    final seatId = d['seat'];
    if (seatId is! int || seatId < 0 || seatId > 2) {
      throw const FormatException('无效座位');
    }
    final seat = PlayerSeat.values[seatId];
    final state = PublicGameState.fromWire(
      Map<String, Object?>.from(d['public'] as Map),
    );
    final hand = (d['hand'] as List).cast<int>();
    if (hand.length != state.counts[seat.index] ||
        hand.toSet().length != hand.length ||
        hand.any((id) => id < 0 || id > 53) ||
        hand.any(state.played.contains) ||
        seat != state.landlord && hand.any(state.bottom.contains)) {
      throw const FormatException('无效的私有手牌');
    }
    return DouDizhuPlayerView(seat: seat, publicState: state, hand: hand);
  }
}
