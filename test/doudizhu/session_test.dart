import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/doudizhu/doudizhu.dart';

void main() {
  test(
    'deal, bidding, landlord twenty and strict rejection without mutation',
    () {
      final s = DouDizhuSession(random: Random(5))..deal();
      expect(s.publicState.counts, [17, 17, 17]);
      expect(s.publicState.bottom, isEmpty);
      expect(s.validateConservation(), isTrue);
      String signature() => jsonEncode([
        for (final seat in PlayerSeat.values) s.view(seat).toWire(),
      ]);
      final before = signature();
      expect(() => s.bid(PlayerSeat.seat1, 1), throwsStateError);
      expect(signature(), before);
      s.bid(PlayerSeat.seat0, 1);
      expect(() => s.bid(PlayerSeat.seat1, 1), throwsStateError);
      s.bid(PlayerSeat.seat1, 2);
      s.bid(PlayerSeat.seat2, 0);
      expect(s.landlord, PlayerSeat.seat1);
      expect(s.turn, PlayerSeat.seat1);
      expect(s.publicState.counts, [17, 20, 17]);
      expect(s.publicState.bottom.length, 3);
      final playing = signature();
      expect(() => s.pass(s.turn), throwsStateError);
      expect(
        () => s.play(s.turn, [
          s.view(s.turn).hand.first,
          s.view(s.turn).hand.first,
        ]),
        throwsStateError,
      );
      expect(
        () => s.play(s.turn, [s.view(PlayerSeat.seat0).hand.first]),
        throwsStateError,
      );
      expect(signature(), playing);
    },
  );
  test('three passes redeal, score three immediately selects landlord', () {
    final s = DouDizhuSession(random: Random(1))..deal();
    final first = s.view(PlayerSeat.seat0).hand.toSet();
    for (var i = 0; i < 3; i++) {
      s.bid(s.turn, 0);
    }
    expect(s.dealNumber, 2);
    expect(s.turn, PlayerSeat.seat1);
    expect(s.view(PlayerSeat.seat0).hand.toSet(), isNot(first));
    expect(s.publicState.bottom, isEmpty);
    expect(s.publicState.bids, [null, null, null]);
    s.bid(s.turn, 3);
    expect(s.phase, DouDizhuPhase.playing);
    expect(s.turn, s.landlord);
    expect(s.validateConservation(), isTrue);
  });
  test('two consecutive passes restore leader and clear trick', () {
    final s = DouDizhuSession(random: Random(2))..deal();
    s.bid(s.turn, 3);
    final leader = s.turn;
    s.play(leader, [s.view(leader).hand.first]);
    s.pass(s.turn);
    expect(s.trick.passes, 1);
    s.pass(s.turn);
    expect(s.turn, leader);
    expect(s.trick.cardIds, isEmpty);
    expect(s.trick.seat, isNull);
    expect(() => s.pass(leader), throwsStateError);
  });
  test(
    'public serialization and one-seat views do not contain hidden cards',
    () {
      final s = DouDizhuSession(random: Random(3))..deal();
      final public = s.publicState.toWire();
      expect(
        public.keys,
        unorderedEquals([
          'phase',
          'turn',
          'counts',
          'bids',
          'bottom',
          'played',
          'history',
          'landlord',
          'winner',
          'winningSeat',
          'dealNumber',
          'trick',
        ]),
      );
      expect(public['bottom'], isEmpty);
      expect(public['played'], isEmpty);
      final hands = [for (final seat in PlayerSeat.values) s.view(seat).hand];
      for (final seat in PlayerSeat.values) {
        final wire = jsonDecode(jsonEncode(s.view(seat).toWire())) as Map;
        expect(wire.keys, unorderedEquals(['seat', 'public', 'hand']));
        final replica = DouDizhuPlayerView.fromWire(
          Map<String, Object?>.from(wire),
        );
        expect(replica.hand, hands[seat.index]);
        expect(
          replica.hand.toSet().intersection(hands[seat.next.index].toSet()),
          isEmpty,
        );
      }
    },
  );
  test('history records public actions, snapshots and resets', () {
    final s = DouDizhuSession(random: Random(2))..deal();
    s.bid(s.turn, 3);
    final actor = s.turn;
    final ids = [s.view(actor).hand.first];
    s.play(actor, ids);
    ids.clear();
    final snapshot = s.publicState;
    s.pass(s.turn);
    s.pass(s.turn);
    expect(snapshot.history!.length, 1);
    expect(snapshot.history!.single.cardIds.length, 1);
    expect(() => snapshot.history!.clear(), throwsUnsupportedError);
    final restored = PublicGameState.fromWire(
      Map<String, Object?>.from(jsonDecode(jsonEncode(s.publicState.toWire()))),
    );
    expect(restored.history!.map((p) => p.seat), PlayerSeat.values);
    expect(restored.history!.map((p) => p.cardIds.length), [1, 0, 0]);
    expect(() => s.pass(s.turn), throwsStateError);
    expect(s.publicState.history!.length, 3);
    final forged = s.publicState.toWire();
    forged['history'] = [
      {
        'seat': 0,
        'cards': [53],
      },
    ];
    expect(() => PublicGameState.fromWire(forged), throwsFormatException);
    final legacy = s.publicState.toWire()..remove('history');
    expect(PublicGameState.fromWire(legacy).history, isNull);
    s.deal();
    expect(s.publicState.history, isEmpty);
    s.close();
    expect(s.publicState.history, isEmpty);
  });
  test(
    'complete games conserve cards, both team outcomes and terminal rejection',
    () {
      final winners = <DouDizhuTeam>{};
      for (var seed = 0; seed < 20; seed++) {
        final s = DouDizhuSession(random: Random(seed))..deal();
        s.bid(s.turn, 3);
        for (
          var moves = 0;
          moves < 400 && s.phase != DouDizhuPhase.finished;
          moves++
        ) {
          final view = s.view(s.turn);
          final cards = const DouDizhuAi().choosePlay(view);
          if (cards.isEmpty) {
            s.pass(s.turn);
          } else {
            s.play(s.turn, cards);
          }
          expect(s.validateConservation(), isTrue);
          PublicGameState.fromWire(s.publicState.toWire());
        }
        expect(s.phase, DouDizhuPhase.finished);
        winners.add(s.winner!);
        expect(
          s.winner,
          s.winningSeat == s.landlord
              ? DouDizhuTeam.landlord
              : DouDizhuTeam.farmers,
        );
        expect(() => s.bid(s.turn, 3), throwsStateError);
        expect(() => s.pass(s.turn), throwsStateError);
        expect(() => s.play(s.turn, [1]), throwsStateError);
        s.close();
        expect(s.publicState.counts, [0, 0, 0]);
      }
      expect(winners, containsAll(DouDizhuTeam.values));
    },
  );
  test(
    'AI consumes round-tripped limited player view, bidding follows score',
    () async {
      final s = DouDizhuSession(random: Random(9))..deal();
      final v = DouDizhuPlayerView.fromWire(s.view(s.turn).toWire());
      final score = const BiddingPolicy().choose(v);
      expect(score, inInclusiveRange(0, 3));
      s.bid(s.turn, 3);
      final play = await const DouDizhuAi().chooseAsync(s.view(s.turn));
      expect(play, isNotEmpty);
      s.play(s.turn, play);
      expect(s.validateConservation(), isTrue);
    },
  );
}
