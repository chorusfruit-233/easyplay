import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tools/benchmark_gomoku_ai.dart' show benchmarkGomokuAi;

void main() {
  test(
    'beats the shipped AI with paired openings and equal node budgets',
    () async {
      // A generous wall limit makes the node-limited result reproducible across
      // CI machines. Six openings, both colors and all three rule variants.
      final report = await benchmarkGomokuAi(maxPlies: 120);
      final games = report['games']! as int;
      final wins = report['newWins']! as int;
      final records = report['records']! as List<Map<String, Object?>>;
      debugPrint(
        'Gomoku AI: $wins/$games wins vs v1.7.0; '
        'legacy ${report['legacyWins']}, draws ${report['draws']}, '
        'unfinished ${report['unfinished']}',
      );
      expect(wins, greaterThan(games ~/ 2));
      for (final side in ['black', 'white']) {
        final paired = records
            .where((record) => record['newSide'] == side)
            .toList();
        expect(
          paired.where((r) => r['result'] == 'new').length,
          greaterThan(paired.length ~/ 2),
          reason: 'Improvement must hold for both colors',
        );
      }
      // Capped games are retained in the denominator, never counted as wins.
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
