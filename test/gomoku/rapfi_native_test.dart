import 'dart:io';

import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/engine/rapfi_io.dart';
import 'package:easyplay/gomoku/engine/rapfi_player.dart';
import 'package:easyplay/gomoku/gomoku_ai_level.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final executable = Platform.environment['RAPFI_TEST_EXECUTABLE'];
  RapfiPlayer engine() => RapfiPlayer(
    transportFactory: () => ProcessRapfiTransport(
      executable: executable!,
      workingDirectory: '${Directory.current.path}/assets/rapfi',
    ),
  );

  test(
    'real ARM64 Rapfi finishes Soosõrv-8 and resumes after cancellation/pass',
    () async {
      final ai = engine();
      addTearDown(ai.dispose);
      final session = GomokuSession();
      for (var i = 0; i < 24 && session.moves.length < 7; i++) {
        final before = session.toJson();
        final action = await ai.decide(session, level: GomokuAiLevel.beginner);
        expect(session.toJson(), before);
        expect(action, isNotNull, reason: ai.failureReason);
        expect(session.applyAction(action!), isTrue);
      }
      expect(session.moves.length, greaterThanOrEqualTo(7));
      expect(session.declaredProposals, inInclusiveRange(1, 8));
      final restored = GomokuSession.fromJson(session.toJson());
      expect(restored.pass(), isTrue);
      final action = await ai.decide(restored, level: GomokuAiLevel.beginner);
      expect(action, isNotNull, reason: ai.failureReason);
      expect(restored.applyAction(action!), isTrue);
      final cancelled = ai.decide(restored, level: GomokuAiLevel.advanced);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      ai.cancel();
      expect(await cancelled, isNull);
      final resumed = await ai.decide(restored, level: GomokuAiLevel.beginner);
      expect(resumed, isNotNull, reason: ai.failureReason);
      expect(restored.applyAction(resumed!), isTrue);
    },
    skip: executable == null
        ? 'Set RAPFI_TEST_EXECUTABLE for real native engine'
        : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'real Rapfi handles N=8, both swaps, all proposals and white selection',
    () async {
      final ai = engine();
      addTearDown(ai.dispose);
      final session = GomokuSession()
        ..place(const Cell(7, 7))
        ..place(const Cell(6, 7))
        ..place(const Cell(6, 6))
        ..exchangeColors(true)
        ..place(const Cell(8, 8))
        ..declareProposals(8);
      final exchange = await ai.decide(session, level: GomokuAiLevel.beginner);
      expect(
        exchange?.type,
        GomokuActionType.exchange,
        reason: ai.failureReason,
      );
      expect(session.applyAction(exchange!), isTrue);
      for (var i = 0; i < 8; i++) {
        final action = await ai.decide(session, level: GomokuAiLevel.beginner);
        expect(action, isNotNull, reason: ai.failureReason);
        expect(session.applyAction(action!), isTrue);
        expect(session.moves, hasLength(4));
      }
      expect(session.proposals, hasLength(8));
      expect(session.phase, GomokuPhase.selection);
      final selection = await ai.decide(session, level: GomokuAiLevel.beginner);
      expect(selection, isNotNull, reason: ai.failureReason);
      expect(session.applyAction(selection!), isTrue);
      expect(session.moves, hasLength(5));
      expect(session.turn, Side.white);
      expect(session.proposals, isEmpty);
    },
    skip: executable == null
        ? 'Set RAPFI_TEST_EXECUTABLE for real native engine'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'real Rapfi finds a Renju immediate win for black',
    () async {
      final ai = engine();
      addTearDown(ai.dispose);
      final session = GomokuSession(variant: GomokuVariant.renju);
      for (var col = 3; col <= 6; col++) {
        expect(session.place(Cell(7, col)), isTrue);
        expect(session.place(Cell(0, (col - 3) * 2)), isTrue);
      }
      final action = await ai.decide(session, level: GomokuAiLevel.advanced);
      expect(action, isNotNull, reason: ai.failureReason);
      expect(session.applyAction(action!), isTrue);
      expect(session.gameOver, isTrue);
      expect(session.winner, Side.black);
    },
    skip: executable == null
        ? 'Set RAPFI_TEST_EXECUTABLE for real native engine'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
