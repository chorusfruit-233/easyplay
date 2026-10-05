import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/doudizhu/doudizhu.dart';

List<PlayingCard> cards(List<int> ranks) {
  final counts = <int, int>{};
  return [
    for (final rank in ranks)
      PlayingCard(
        rank >= 16
            ? rank + 36
            : (rank - 3) * 4 +
                  counts.update(rank, (n) => n + 1, ifAbsent: () => 0),
      ),
  ];
}

void main() {
  test('54 unique physical cards and all ranks/suits', () {
    final deck = PlayingCard.deck(random: Random(4));
    expect(deck.map((c) => c.id).toSet().length, 54);
    expect(deck.where((c) => c.rank == 15).length, 4);
    expect(deck.where((c) => c.suit == CardSuit.joker).length, 2);
    expect(() => PlayingCard(54), throwsArgumentError);
  });
  final cases = <PlayType, List<int>>{
    PlayType.single: [3],
    PlayType.pair: [4, 4],
    PlayType.triple: [5, 5, 5],
    PlayType.tripleSingle: [6, 6, 6, 16],
    PlayType.triplePair: [6, 6, 6, 7, 7],
    PlayType.straight: [3, 4, 5, 6, 7],
    PlayType.pairStraight: [3, 3, 4, 4, 5, 5],
    PlayType.airplane: [3, 3, 3, 4, 4, 4],
    PlayType.airplaneSingles: [3, 3, 3, 4, 4, 4, 7, 16],
    PlayType.airplanePairs: [3, 3, 3, 4, 4, 4, 7, 7, 8, 8],
    PlayType.fourSingles: [3, 3, 3, 3, 5, 5],
    PlayType.fourPairs: [3, 3, 3, 3, 5, 5, 6, 6],
    PlayType.bomb: [15, 15, 15, 15],
    PlayType.rocket: [16, 17],
  };
  for (final e in cases.entries) {
    test('classify ${e.key.name}, independent of UI order', () {
      final c = cards(e.value);
      expect(classifyPlay(c)?.type, e.key);
      expect(classifyPlay(c.reversed.toList())?.type, e.key);
      expect(classifyPlay(c..shuffle(Random(42)))?.type, e.key);
    });
  }
  test('all explicit profile boundaries and duplicate IDs', () {
    for (final ranks in [
      <int>[],
      [11, 12, 13, 14, 15],
      [3, 3, 4, 4],
      [3, 3, 3, 15, 15, 15],
      [3, 3, 3, 4, 4, 4, 7, 7],
      [3, 3, 3, 4, 4, 4, 16, 17],
      [3, 3, 3, 3, 16, 17],
      [3, 3, 3, 3, 5, 5, 5, 5],
      [3, 3, 3, 3, 4, 4, 4, 5],
      [3, 4, 5, 6],
    ]) {
      expect(classifyPlay(cards(ranks)), isNull, reason: '$ranks');
    }
    expect(classifyPlay([PlayingCard(0), PlayingCard(0)]), isNull);
    expect(
      classifyPlay(cards([3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6]))?.sequenceLength,
      4,
    );
    expect(
      classifyPlay(cards([3, 3, 3, 4, 4, 4, 5, 5, 5, 7, 8, 16]))?.type,
      PlayType.airplaneSingles,
    );
  });
  test('bomb and rocket have explicit cross-type ordering', () {
    PlayPattern p(List<int> ranks) => classifyPlay(cards(ranks))!;
    expect(canBeat(p([4]), p([3])), isTrue);
    expect(canBeat(p([3, 3]), p([4])), isFalse);
    expect(canBeat(p([3, 4, 5, 6, 7, 8]), p([3, 4, 5, 6, 7])), isFalse);
    expect(canBeat(p([3, 3, 3, 3]), p([15, 15, 15])), isTrue);
    expect(canBeat(p([4, 4, 4, 4]), p([3, 3, 3, 3])), isTrue);
    expect(canBeat(p([16, 17]), p([15, 15, 15, 15])), isTrue);
    expect(canBeat(p([16, 17]), p([16, 17])), isFalse);
    expect(canBeat(p([15, 15, 15, 15]), p([16, 17])), isFalse);
  });
  test(
    'generator returns owned legal distinct cards and every rank pattern',
    () {
      // Compare to exhaustive small-hand enumeration, rather than mirroring it.
      final random = Random(86);
      for (var i = 0; i < 25; i++) {
        final hand = PlayingCard.deck(random: random).take(10).toList();
        String key(List<PlayingCard> c) =>
            (c.map((c) => c.rank).toList()..sort()).join(',');
        final expected = <String>{};
        for (var mask = 1; mask < 1 << hand.length; mask++) {
          final subset = [
            for (var j = 0; j < hand.length; j++)
              if (mask & (1 << j) != 0) hand[j],
          ];
          if (classifyPlay(subset) != null) expected.add(key(subset));
        }
        final generated = const LegalPlayGenerator().generate(
          hand,
          const TrickState(),
        );
        expect(
          generated
              .map((ids) => key(ids.map(PlayingCard.new).toList()))
              .toSet(),
          expected,
        );
        for (final ids in generated) {
          expect(ids.toSet().length, ids.length);
          expect(ids.every((id) => hand.any((c) => c.id == id)), isTrue);
        }
      }
    },
  );
  test('generator enumerates airplanes and filters by previous play', () {
    for (final e in cases.entries) {
      final hand = cards(e.value);
      expect(
        const LegalPlayGenerator()
            .generate(hand, const TrickState())
            .any((ids) => ids.length == hand.length),
        isTrue,
        reason: e.key.name,
      );
    }
    final hand = cards([3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 16, 17]);
    final trick = TrickState(
      seat: PlayerSeat.seat1,
      cardIds: cards([3, 3]).map((c) => c.id).toList(),
    );
    for (final ids in const LegalPlayGenerator().generate(hand, trick)) {
      expect(
        canBeat(
          classifyPlay(ids.map(PlayingCard.new).toList())!,
          classifyPlay(cards([3, 3]))!,
        ),
        isTrue,
      );
    }
  });
}
