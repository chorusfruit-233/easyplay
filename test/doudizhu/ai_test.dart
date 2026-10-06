import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/doudizhu/doudizhu.dart';
import 'package:easyplay/doudizhu/ai/hand_plan.dart';
import 'package:easyplay/doudizhu/ai/public_cards.dart';

List<int> cards(List<int> ranks) {
  final used = <int, int>{};
  return [
    for (final rank in ranks)
      if (rank >= 16)
        rank + 36
      else
        (rank - 3) * 4 + used.update(rank, (n) => n + 1, ifAbsent: () => 0),
  ];
}

DouDizhuPlayerView position({
  required List<int> hand,
  PlayerSeat seat = PlayerSeat.seat0,
  PlayerSeat landlord = PlayerSeat.seat0,
  List<int>? landlordHand,
  Map<PlayerSeat, List<int>> otherHands = const {},
  List<int> counts = const [12, 10, 10],
  TrickState trick = const TrickState(),
}) {
  final occupied = {...hand, ...trick.cardIds};
  final hands = List.generate(3, (_) => <int>[]);
  hands[seat.index] = hand;
  if (landlord != seat && landlordHand != null) {
    hands[landlord.index] = landlordHand;
    occupied.addAll(landlordHand);
  }
  for (final entry in otherHands.entries) {
    hands[entry.key.index] = entry.value;
    occupied.addAll(entry.value);
  }
  final available = [
    for (var id = 0; id < 54; id++)
      if (!occupied.contains(id)) id,
  ];
  for (final s in PlayerSeat.values) {
    if (s == seat || hands[s.index].isNotEmpty) continue;
    hands[s.index] = available.take(counts[s.index]).toList();
    available.removeRange(0, counts[s.index]);
  }
  final held = hands.expand((h) => h).toSet();
  final played = [
    for (var id = 0; id < 54; id++)
      if (!held.contains(id)) id,
  ];
  final bottom = [...hands[landlord.index].take(3)];
  bottom.addAll(
    played.where((id) => !trick.cardIds.contains(id)).take(3 - bottom.length),
  );
  final view = DouDizhuPlayerView(
    seat: seat,
    hand: hand,
    publicState: PublicGameState(
      phase: DouDizhuPhase.playing,
      turn: seat,
      landlord: landlord,
      counts: hands.map((h) => h.length).toList(),
      bids: const [3, 0, 0],
      bottom: bottom,
      played: played,
      trick: trick,
    ),
  );
  return DouDizhuPlayerView.fromWire(view.toWire());
}

void main() {
  const ai = DouDizhuAi();
  test('hand planning recognizes straights, airplanes and paired wings', () {
    for (final ranks in [
      [3, 4, 5, 6, 7, 8],
      [3, 3, 4, 4, 5, 5],
      [3, 3, 3, 4, 4, 4, 8, 9],
      [3, 3, 3, 4, 4, 4, 8, 8, 9, 9],
    ]) {
      expect(HandPlan(cards(ranks)).initialTurns, 1);
    }
    expect(HandPlan(cards([3, 3, 3, 4, 4, 4, 6, 7, 8, 9, 10])).initialTurns, 2);
  });
  test('farmers do not steal a teammate lead or bomb a teammate', () {
    for (final hand in [
      cards([8, 8, 9, 9, 15, 15]),
      cards([8, 8, 8, 8, 13, 13]),
    ]) {
      final view = position(
        hand: hand,
        seat: PlayerSeat.seat2,
        trick: TrickState(seat: PlayerSeat.seat1, cardIds: cards([7])),
      );
      expect(ai.choosePlay(view), isEmpty);
    }
  });
  test('finishing the whole hand takes priority over yielding to partner', () {
    final view = position(
      hand: cards([15, 15]),
      seat: PlayerSeat.seat2,
      trick: TrickState(seat: PlayerSeat.seat1, cardIds: cards([8, 8])),
    );
    expect(ai.choosePlay(view), unorderedEquals(view.hand));
  });
  test('intercept landlord who could finish over the partner on next turn', () {
    final view = position(
      hand: cards([12, 12, 15, 3, 3]),
      seat: PlayerSeat.seat2,
      landlordHand: cards([14]),
      counts: const [1, 4, 5],
      trick: TrickState(seat: PlayerSeat.seat1, cardIds: cards([7])),
    );
    expect(ai.choosePlay(view).map((id) => PlayingCard(id).rank), [15]);
  });
  test('lead a pair rather than giving an opponent with one card a single', () {
    final view = position(
      hand: cards([3, 3, 4, 14, 14]),
      counts: const [5, 1, 1],
      otherHands: {
        PlayerSeat.seat1: cards([15]),
        PlayerSeat.seat2: cards([13]),
      },
    );
    final choice = ai.choosePlay(view);
    expect(
      classifyPlay(choice.map(PlayingCard.new).toList())!.type,
      PlayType.pair,
    );
  });
  test('feed a low single to the next farmer with one card left', () {
    final view = position(
      hand: cards([3, 4, 5, 6, 7, 9, 9]),
      seat: PlayerSeat.seat1,
      counts: const [14, 7, 1],
    );
    final choice = ai.choosePlay(view);
    expect(choice.length, 1);
    expect(PlayingCard(choice.single).rank, 3);
  });
  test('a secure control card is played before the last weak combination', () {
    final view = position(hand: cards([3, 3, 17]), counts: const [3, 3, 3]);
    expect(ai.choosePlay(view), [53]);
  });
  test(
    'public card counting assigns known bottom cards and excludes played cards',
    () {
      final view = position(
        hand: cards([3, 3, 9, 9]),
        seat: PlayerSeat.seat1,
        landlordHand: cards([14]),
        counts: const [1, 4, 5],
      );
      final knowledge = PublicCards(view);
      expect(knowledge.known(PlayerSeat.seat0), cards([14]));
      expect(
        knowledge.unknown.toSet().intersection({
          ...view.hand,
          ...view.publicState.played,
          ...knowledge.landlordCards,
        }),
        isEmpty,
      );
      expect(
        knowledge.chanceToBeat(
          PlayerSeat.seat0,
          classifyPlay(cards([13]).map(PlayingCard.new).toList())!,
        ),
        1,
      );
      expect(
        knowledge.chanceToBeat(
          PlayerSeat.seat0,
          classifyPlay(cards([15]).map(PlayingCard.new).toList())!,
        ),
        0,
      );
      for (var seed = 0; seed < 8; seed++) {
        final hands = knowledge.sample(Random(seed))!;
        expect(hands.map((h) => h.length), view.publicState.counts);
        expect(hands[0], knowledge.landlordCards);
        expect(hands[1], view.hand);
        expect(
          hands.expand((h) => h).toSet().length,
          hands.expand((h) => h).length,
        );
      }
    },
  );
  test(
    'bidding accounts for shape and fragmented hands, never repeats highest bid',
    () {
      DouDizhuPlayerView bidView(List<int> ranks, {int highest = 0}) =>
          DouDizhuPlayerView(
            seat: PlayerSeat.seat0,
            hand: cards(ranks),
            publicState: PublicGameState(
              phase: DouDizhuPhase.bidding,
              turn: PlayerSeat.seat0,
              counts: const [17, 17, 17],
              bids: [null, highest, null],
              bottom: const [],
              played: const [],
              trick: const TrickState(),
            ),
          );
      const policy = BiddingPolicy();
      final organized = [
        3,
        3,
        3,
        4,
        4,
        4,
        5,
        5,
        5,
        6,
        6,
        6,
        14,
        14,
        15,
        16,
        17,
      ];
      expect(policy.choose(bidView(organized)), 3);
      expect(policy.choose(bidView(organized, highest: 3)), 0);
      expect(
        policy.choose(
          bidView([3, 4, 6, 8, 10, 12, 13, 3, 4, 6, 8, 10, 12, 13, 5, 7, 9]),
        ),
        0,
      );
    },
  );
  test(
    'physical card order does not change rank decisions or mutate the view',
    () {
      final session = DouDizhuSession(random: Random(24))..deal();
      session.bid(session.turn, 3);
      final view = session.view(session.turn);
      final original = view.hand.toList();
      final reordered = DouDizhuPlayerView(
        seat: view.seat,
        publicState: view.publicState,
        hand: view.hand.reversed,
      );
      List<int> ranks(List<int> ids) =>
          ids.map((id) => PlayingCard(id).rank).toList()..sort();
      expect(ranks(ai.choosePlay(view)), ranks(ai.choosePlay(reordered)));
      expect(view.hand, original);
    },
  );
  test('native asynchronous policy matches the synchronous choice', () async {
    final session = DouDizhuSession(random: Random(33))..deal();
    session.bid(session.turn, 3);
    final view = session.view(session.turn);
    expect(await ai.chooseAsync(view), ai.choosePlay(view));
  });
}
