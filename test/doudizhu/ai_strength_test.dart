import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/doudizhu/doudizhu.dart';
import 'legacy_ai.dart' show LegacyDouDizhuAi;

void main() {
  test(
    'new policy beats the previous policy on paired deals and both teams',
    () {
      var wins = 0, games = 0, landlordWins = 0, farmerWins = 0;
      final stopwatch = Stopwatch()..start();
      var maxMicros = 0;
      const seedOffset = int.fromEnvironment(
        'DDZ_AI_SEED_OFFSET',
        defaultValue: 1000,
      );
      const deals = int.fromEnvironment('DDZ_AI_DEALS', defaultValue: 300);
      for (var seed = seedOffset; seed < seedOffset + deals; seed++) {
        for (final newLandlord in [true, false]) {
          final session = DouDizhuSession(random: Random(seed))..deal();
          // Rotate the landlord, preserving the exact deal in each paired game.
          final landlord = PlayerSeat.values[seed % 3];
          while (session.turn != landlord) {
            session.bid(session.turn, 0);
          }
          session.bid(session.turn, 3);
          for (
            var move = 0;
            move < 400 && session.phase != DouDizhuPhase.finished;
            move++
          ) {
            final view = session.view(session.turn);
            final useNew = (view.seat == landlord) == newLandlord;
            final timer = Stopwatch()..start();
            final choice = useNew
                ? const DouDizhuAi().choosePlay(view)
                : const LegacyDouDizhuAi().choosePlay(view);
            if (useNew) maxMicros = max(maxMicros, timer.elapsedMicroseconds);
            if (choice.isEmpty) {
              session.pass(session.turn);
            } else {
              session.play(session.turn, choice);
            }
            expect(session.validateConservation(), isTrue);
          }
          expect(
            session.phase,
            DouDizhuPhase.finished,
            reason: 'seed $seed, newLandlord $newLandlord',
          );
          if ((session.winner == DouDizhuTeam.landlord) == newLandlord) {
            wins++;
            if (newLandlord) {
              landlordWins++;
            } else {
              farmerWins++;
            }
          }
          games++;
          session.close();
        }
      }
      // Role balance prevents an easy farmer/landlord distribution from hiding
      // regressions. This gate measures improvement over the shipped opponent.
      debugPrint(
        'AI comparison: $wins/$games wins (landlord $landlordWins, farmers $farmerWins); ${stopwatch.elapsedMilliseconds}ms total, ${maxMicros ~/ 1000}ms maximum new decision.',
      );
      expect(wins, greaterThan(games ~/ 2));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
