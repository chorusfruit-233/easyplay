import 'dart:math';
import 'doudizhu_model.dart';
import 'doudizhu_rules.dart';

class DouDizhuSession {
  DouDizhuSession({Random? random}) : _random = random ?? Random.secure();
  final Random _random;
  final _hands = List.generate(3, (_) => <int>[]);
  List<int> _bottom = [], _played = [];
  List<int?> _bids = [null, null, null];
  DouDizhuPhase phase = DouDizhuPhase.waiting;
  PlayerSeat turn = PlayerSeat.seat0;
  PlayerSeat? landlord, winningSeat;
  DouDizhuTeam? winner;
  TrickState trick = const TrickState();
  int dealNumber = 0;

  void deal() {
    phase = DouDizhuPhase.dealing;
    final deck = PlayingCard.deck(random: _random).map((c) => c.id).toList();
    for (var i = 0; i < 3; i++) {
      _hands[i]
        ..clear()
        ..addAll(deck.sublist(i * 17, (i + 1) * 17));
    }
    _bottom = deck.sublist(51);
    _played = [];
    _bids = [null, null, null];
    landlord = null;
    winner = null;
    winningSeat = null;
    trick = const TrickState();
    turn = PlayerSeat.values[dealNumber % 3];
    dealNumber++;
    phase = DouDizhuPhase.bidding;
    assert(validateConservation());
  }

  void bid(PlayerSeat seat, int score) {
    if (phase != DouDizhuPhase.bidding || seat != turn) {
      throw StateError('尚未轮到你叫分');
    }
    final highest = _bids.whereType<int>().fold(0, max);
    if (score < 0 || score > 3 || (score != 0 && score <= highest)) {
      throw StateError('叫分必须高于当前最高分');
    }
    _bids[seat.index] = score;
    if (score == 3 || _bids.every((s) => s != null)) {
      final top = _bids.whereType<int>().fold(0, max);
      if (top == 0) {
        deal();
        return;
      }
      landlord = PlayerSeat.values[_bids.indexOf(top)];
      _hands[landlord!.index].addAll(_bottom);
      turn = landlord!;
      phase = DouDizhuPhase.playing;
    } else {
      turn = turn.next;
    }
    assert(validateConservation());
  }

  void play(PlayerSeat seat, List<int> ids) {
    if (phase != DouDizhuPhase.playing || turn != seat) {
      throw StateError('尚未轮到你出牌');
    }
    if (ids.isEmpty ||
        ids.toSet().length != ids.length ||
        ids.any((id) => !_hands[seat.index].contains(id))) {
      throw StateError('请选择自己持有的牌，不能重复');
    }
    final pattern = classifyPlay(ids.map(PlayingCard.new).toList());
    if (pattern == null) throw StateError('选牌不是合法牌型');
    final previous = classifyPlay(trick.cardIds.map(PlayingCard.new).toList());
    if (previous != null && !canBeat(pattern, previous)) {
      throw StateError('所选牌不能压过上一手');
    }
    _hands[seat.index].removeWhere(ids.contains);
    _played.addAll(ids);
    trick = TrickState(seat: seat, cardIds: List.unmodifiable(ids));
    if (_hands[seat.index].isEmpty) {
      winningSeat = seat;
      winner = seat == landlord ? DouDizhuTeam.landlord : DouDizhuTeam.farmers;
      phase = DouDizhuPhase.finished;
    } else {
      turn = turn.next;
    }
    assert(validateConservation());
  }

  void pass(PlayerSeat seat) {
    if (phase != DouDizhuPhase.playing || seat != turn) {
      throw StateError('尚未轮到你');
    }
    if (trick.seat == null || trick.seat == seat) throw StateError('领出玩家不能不要');
    if (trick.passes == 1) {
      turn = trick.seat!;
      trick = const TrickState();
    } else {
      trick = TrickState(seat: trick.seat, cardIds: trick.cardIds, passes: 1);
      turn = turn.next;
    }
  }

  PublicGameState get publicState => PublicGameState(
    phase: phase,
    turn: turn,
    counts: List.unmodifiable(_hands.map((h) => h.length)),
    bids: List.unmodifiable(_bids),
    bottom: List.unmodifiable(landlord == null ? <int>[] : _bottom),
    played: List.unmodifiable(_played),
    trick: trick,
    landlord: landlord,
    winner: winner,
    winningSeat: winningSeat,
    dealNumber: dealNumber,
  );
  DouDizhuPlayerView view(PlayerSeat seat) => DouDizhuPlayerView(
    seat: seat,
    publicState: publicState,
    hand: _hands[seat.index],
  );
  bool validateConservation() {
    if (phase == DouDizhuPhase.waiting) return _hands.every((h) => h.isEmpty);
    final cards = [
      ..._hands.expand((h) => h),
      ..._played,
      if (landlord == null) ..._bottom,
    ];
    return cards.length == 54 &&
        cards.toSet().length == 54 &&
        cards.every((id) => id >= 0 && id < 54);
  }

  void close() {
    for (final h in _hands) {
      h.clear();
    }
    _bottom.clear();
    _played.clear();
    _bids = [null, null, null];
    landlord = null;
    winner = null;
    winningSeat = null;
    phase = DouDizhuPhase.waiting;
    trick = const TrickState();
  }
}
