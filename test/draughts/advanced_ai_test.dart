import 'dart:math';

import 'package:easyplay/draughts/draughts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'advanced searches four plies in the international opening within 1600 nodes',
    () async {
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.international),
      );
      final before = session.toJson();
      final result = await DraughtsAi(random: Random(42)).search(
        session,
        level: DraughtsAiLevel.advanced,
        maxNodes: 1600,
        timeLimit: const Duration(seconds: 5),
      );
      // The frozen advanced engine completes only three plies with this budget.
      expect(result!.depth, greaterThanOrEqualTo(4));
      expect(result.nodes, lessThanOrEqualTo(1600));
      expect(session.legalMoves(), contains(result.move));
      expect(session.toJson(), before);
    },
  );

  for (final variant in DraughtsVariant.values) {
    test(
      'advanced geometry, capture and budget checks for ${variant.name}',
      () async {
        final session = DraughtsSession(DraughtsRules.forVariant(variant));
        final before = session.toJson();
        final result = await DraughtsAi(random: Random(42)).search(
          session,
          level: DraughtsAiLevel.advanced,
          maxNodes: 200,
          maxDepth: 2,
          timeLimit: const Duration(seconds: 5),
        );
        expect(result!.depth, lessThanOrEqualTo(2));
        expect(result.nodes, lessThanOrEqualTo(200));
        expect(session.legalMoves(), contains(result.move));
        expect(session.toJson(), before);
      },
    );
  }

  test('advanced cancellation rejects a result during deeper search', () async {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.turkish),
    );
    final before = session.toJson();
    final ai = DraughtsAi();
    final pending = ai.search(
      session,
      level: DraughtsAiLevel.advanced,
      maxDepth: 20,
      maxNodes: 100000,
      timeLimit: const Duration(seconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ai.cancel();
    expect(await pending, isNull);
    expect(session.toJson(), before);
  });
}
