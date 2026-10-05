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
    final t = Map<String, Object?>.from(d['trick'] as Map);
    final counts = (d['counts'] as List).cast<int>();
    final bids = (d['bids'] as List).cast<int?>();
    if (counts.length != 3 ||
        bids.length != 3 ||
        counts.any((n) => n < 0 || n > 20)) {
      throw const FormatException('无效的公共状态');
    }
    return PublicGameState(
      phase: DouDizhuPhase.values.byName(d['phase'] as String),
      turn: PlayerSeat.values[d['turn'] as int],
      counts: List.unmodifiable(counts),
      bids: List.unmodifiable(bids),
      bottom: List.unmodifiable((d['bottom'] as List).cast<int>()),
      played: List.unmodifiable((d['played'] as List).cast<int>()),
      trick: TrickState(
        seat: t['seat'] == null ? null : PlayerSeat.values[t['seat'] as int],
        cardIds: List.unmodifiable((t['cards'] as List).cast<int>()),
        passes: t['passes'] as int,
      ),
      landlord: d['landlord'] == null
          ? null
          : PlayerSeat.values[d['landlord'] as int],
      winner: d['winner'] == null
          ? null
          : DouDizhuTeam.values.byName(d['winner'] as String),
      winningSeat: d['winningSeat'] == null
          ? null
          : PlayerSeat.values[d['winningSeat'] as int],
      dealNumber: d['dealNumber'] as int,
    );
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
    final seat = PlayerSeat.values[d['seat'] as int];
    final state = PublicGameState.fromWire(
      Map<String, Object?>.from(d['public'] as Map),
    );
    final hand = (d['hand'] as List).cast<int>();
    if (hand.length != state.counts[seat.index] ||
        hand.toSet().length != hand.length ||
        hand.any((id) => id < 0 || id > 53) ||
        hand.any(state.played.contains)) {
      throw const FormatException('无效的私有手牌');
    }
    return DouDizhuPlayerView(seat: seat, publicState: state, hand: hand);
  }
}
