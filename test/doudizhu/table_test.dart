import 'package:easyplay/doudizhu/doudizhu_model.dart';
import 'package:easyplay/doudizhu/doudizhu_table.dart';
import 'package:flutter_test/flutter_test.dart';

PublicGameState tableState(
  List<CardPlay> history, {
  TrickState trick = const TrickState(),
  DouDizhuPhase phase = DouDizhuPhase.playing,
}) => PublicGameState(
  phase: phase,
  turn: PlayerSeat.seat0,
  landlord: phase == DouDizhuPhase.bidding ? null : PlayerSeat.seat0,
  counts: phase == DouDizhuPhase.bidding
      ? [17, 17, 17]
      : [
          for (final seat in PlayerSeat.values)
            (seat == PlayerSeat.seat0 ? 20 : 17) -
                history
                    .where((p) => p.seat == seat)
                    .fold(0, (n, p) => n + p.cardIds.length),
        ],
  bids: [3, null, null],
  bottom: phase == DouDizhuPhase.bidding ? [] : [51, 52, 53],
  played: history.expand((p) => p.cardIds).toList(),
  history: history,
  trick: trick,
);

void main() {
  final plays = [
    CardPlay(PlayerSeat.seat0, [0]),
    CardPlay(PlayerSeat.seat1, [4]),
    CardPlay(PlayerSeat.seat2, [8]),
  ];

  test('each player keeps their own cards when another player beats them', () {
    final round = DouDizhuTableRound.fromState(tableState(plays));
    expect(round.plays[PlayerSeat.seat0]!.cards, [0]);
    expect(round.plays[PlayerSeat.seat1]!.cards, [4]);
    expect(round.plays[PlayerSeat.seat2]!.cards, [8]);
    expect(round.topSeat, PlayerSeat.seat2);
    expect(round.complete, isFalse);
  });

  test(
    'passes keep the cards and a completed round waits for the next lead',
    () {
      final history = [
        ...plays,
        CardPlay(PlayerSeat.seat0, []),
        CardPlay(PlayerSeat.seat1, []),
      ];
      final round = DouDizhuTableRound.fromState(tableState(history));
      expect(round.complete, isTrue);
      expect(round.topSeat, PlayerSeat.seat2);
      expect(round.plays[PlayerSeat.seat0]!.cards, [0]);
      expect(round.plays[PlayerSeat.seat0]!.passed, isTrue);
      expect(round.plays[PlayerSeat.seat1]!.cards, [4]);
      expect(round.plays[PlayerSeat.seat1]!.passed, isTrue);
      final next = DouDizhuTableRound.fromState(
        tableState([
          ...history,
          CardPlay(PlayerSeat.seat2, [12]),
        ]),
      );
      expect(next.complete, isFalse);
      expect(next.plays.keys, [PlayerSeat.seat2]);
      expect(next.plays[PlayerSeat.seat2]!.cards, [12]);
      expect(next.plays[PlayerSeat.seat2]!.passed, isFalse);
    },
  );

  test('a new play replaces that player’s cards and clears their pass', () {
    final round = DouDizhuTableRound.fromState(
      tableState([
        ...plays.take(2),
        CardPlay(PlayerSeat.seat2, []),
        CardPlay(PlayerSeat.seat0, [12]),
        CardPlay(PlayerSeat.seat1, []),
        CardPlay(PlayerSeat.seat2, [16]),
      ]),
    );
    expect(round.plays[PlayerSeat.seat0]!.cards, [12]);
    expect(round.plays[PlayerSeat.seat2]!.cards, [16]);
    expect(round.plays[PlayerSeat.seat2]!.passed, isFalse);
  });

  test('fresh reconnect snapshots reconstruct the same completed table', () {
    final state = tableState([
      ...plays,
      CardPlay(PlayerSeat.seat0, []),
      CardPlay(PlayerSeat.seat1, []),
    ]);
    final snapshot = PublicGameState.fromWire(state.toWire());
    final restored = DouDizhuTableRound.fromState(snapshot);
    expect(restored.complete, isTrue);
    expect(restored.plays[PlayerSeat.seat0]!.cards, [0]);
    expect(restored.plays[PlayerSeat.seat1]!.passed, isTrue);
    expect(restored.plays[PlayerSeat.seat2]!.cards, [8]);
    expect(() => restored.plays.clear(), throwsUnsupportedError);
    expect(
      () => restored.plays[PlayerSeat.seat0]!.cards.clear(),
      throwsUnsupportedError,
    );
  });

  test('new deals and bidding have no stale table cards', () {
    expect(
      DouDizhuTableRound.fromState(
        tableState([], phase: DouDizhuPhase.bidding),
      ).plays,
      isEmpty,
    );
  });

  test('old peers without history show only their known current play', () {
    final wire = tableState(
      plays.take(2).toList(),
      trick: const TrickState(seat: PlayerSeat.seat1, cardIds: [4]),
    ).toWire()..remove('history');
    final round = DouDizhuTableRound.fromState(PublicGameState.fromWire(wire));
    expect(round.plays.keys, [PlayerSeat.seat1]);
    expect(round.plays[PlayerSeat.seat1]!.cards, [4]);
  });
}
