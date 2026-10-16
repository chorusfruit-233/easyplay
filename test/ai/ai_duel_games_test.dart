import 'dart:math';

import 'package:easyplay/ai/ai_duel_config.dart';
import 'package:easyplay/ai/ai_duel_controller.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/draughts_ai_duel.dart';
import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_ai_duel.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingGomokuAi extends GomokuAi {
  final levels = <GomokuAiLevel>[];

  @override
  Future<GomokuAiResult?> search(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
    int? maxNodes,
    int? maxDepth,
    Duration? timeLimit,
  }) {
    levels.add(level);
    return super.search(source, level: level, maxDepth: 1, maxNodes: 100);
  }
}

class RecordingDraughtsAi extends DraughtsAi {
  RecordingDraughtsAi() : super(random: Random(7));
  final levels = <DraughtsAiLevel>[];

  @override
  Future<DraughtsAiResult?> search(
    DraughtsSession source, {
    DraughtsAiLevel level = DraughtsAiLevel.intermediate,
    int? maxNodes,
    int? maxDepth,
    Duration? timeLimit,
  }) {
    levels.add(level);
    return super.search(source, level: level, maxDepth: 1, maxNodes: 100);
  }
}

Future<void> finishSearch<M>(
  WidgetTester tester,
  AiDuelController<M> duel,
) async {
  for (var i = 0; i < 300 && duel.thinking; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(duel.thinking, isFalse);
  expect(duel.error, isNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final variant in GomokuVariant.values) {
    testWidgets('Gomoku ${variant.name}: both AIs, save, undo and new record', (
      tester,
    ) async {
      const config = AiDuelConfig(
        blackLevel: GomokuAiLevel.advanced,
        whiteLevel: GomokuAiLevel.beginner,
      );
      final ai = RecordingGomokuAi();
      final duel = GomokuAiDuelController(
        session: GomokuSession(variant: variant),
        config: config,
        ai: ai,
        recordId: 'original',
        initiallyPaused: true,
      );
      addTearDown(duel.dispose);
      duel.start();
      for (var i = 0; i < 2; i++) {
        duel.step();
        await finishSearch(tester, duel);
      }
      expect(ai.levels, [GomokuAiLevel.advanced, GomokuAiLevel.beginner]);
      expect(duel.moveCount, 2);
      final record = (await GomokuStorage.list()).single;
      expect(record.variant, variant);
      expect(record.toJson()['version'], 2);
      expect(record.aiDuel!.toJson(), config.toJson());
      expect(record.restore().toJson(), duel.session.toJson());
      duel.undo();
      expect(duel.turn, Side.white);
      expect(duel.paused, isTrue);
      duel.restart(paused: true);
      final records = await GomokuStorage.list();
      expect(records, hasLength(2));
      expect(records.first.id, isNot('original'));
      expect(records.first.moveCount, 0);
      expect(records.last.moveCount, 1);
      expect(duel.session.variant, variant);
    });
  }

  for (final variant in DraughtsVariant.values) {
    testWidgets(
      'Draughts ${variant.name}: correct first side, legal moves, save and undo',
      (tester) async {
        const config = AiDuelConfig(
          blackLevel: DraughtsAiLevel.advanced,
          whiteLevel: DraughtsAiLevel.beginner,
        );
        final ai = RecordingDraughtsAi();
        final session = DraughtsSession(DraughtsRules.forVariant(variant));
        final firstSide = session.turn;
        final initial = session.position.signature(firstSide);
        final duel = DraughtsAiDuelController(
          session: session,
          config: config,
          ai: ai,
          recordId: 'original',
          initiallyPaused: true,
        );
        addTearDown(duel.dispose);
        duel.start();
        final expected = <DraughtsAiLevel>[];
        for (var i = 0; i < 2; i++) {
          expected.add(config.levelFor(duel.turn));
          duel.step();
          await finishSearch(tester, duel);
        }
        expect(ai.levels, expected);
        expect(duel.moveCount, 2);
        final record = (await DraughtsStorage.list()).single;
        expect(record.kind, DraughtsGameKind.aiDuel);
        expect(record.localSide, isNull);
        expect(record.aiDuel!.toJson(), config.toJson());
        final restored = DraughtsSession.fromJson(record.sessionState);
        expect(restored.toJson(), session.toJson());
        expect(restored.undo(), isTrue);
        expect(restored.undo(), isTrue);
        expect(restored.position.signature(restored.turn), initial);
        duel.undo();
        expect(duel.moveCount, 1);
        duel.restart(paused: true);
        final records = await DraughtsStorage.list();
        expect(records, hasLength(2));
        expect(records.first.id, isNot('original'));
        expect(records.last.moves, hasLength(1));
        expect(duel.session.variant, variant);
        expect(duel.turn, firstSide);
        expect(duel.session.position.signature(duel.turn), initial);
      },
    );
  }

  testWidgets('Gomoku winning move stops autoplay and survives saving', (
    tester,
  ) async {
    final session = GomokuSession();
    for (var col = 3; col <= 6; col++) {
      session.place(Cell(7, col));
      session.place(Cell(4, col));
    }
    final duel = GomokuAiDuelController(
      session: session,
      config: const AiDuelConfig(
        blackLevel: GomokuAiLevel.intermediate,
        whiteLevel: GomokuAiLevel.beginner,
      ),
    );
    addTearDown(duel.dispose);
    duel.start();
    await tester.pump();
    await finishSearch(tester, duel);
    await tester.pump(const Duration(seconds: 3));
    expect(duel.gameOver, isTrue);
    expect(session.winner, Side.black);
    expect(duel.moveCount, 9);
    final saved = (await GomokuStorage.list()).single;
    expect(saved.restore().winner, Side.black);
    expect(saved.aiDuel, isNotNull);
  });

  test('incomplete or unknown AI-duel levels cannot become local games', () {
    final gomoku = GomokuRecord(
      id: 'duel',
      createdAt: DateTime.utc(2026),
      session: GomokuSession(),
    ).toJson();
    for (final settings in [
      null,
      {'blackLevel': 'beginner'},
      {'blackLevel': 'future', 'whiteLevel': 'advanced'},
    ]) {
      expect(
        () => GomokuRecord.fromJson({
          ...gomoku,
          'version': 2,
          'aiDuel': settings,
        }),
        throwsFormatException,
      );
      final draughts = DraughtsRecord.fromSession(
        DraughtsSession(DraughtsRules.forVariant(DraughtsVariant.english)),
      ).toJson();
      expect(
        () => DraughtsRecord.fromJson({
          ...draughts,
          'kind': 'aiDuel',
          'aiDuel': settings,
        }),
        throwsFormatException,
      );
    }
  });
}
