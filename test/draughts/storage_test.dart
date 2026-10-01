import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/game_session.dart' show Side;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('overlapping saves and deletes preserve queue order', () async {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
    );
    await Future.wait([
      DraughtsStorage.save(DraughtsRecord.fromSession(session, id: 'first')),
      DraughtsStorage.save(DraughtsRecord.fromSession(session, id: 'second')),
      DraughtsStorage.delete('first'),
    ]);
    expect((await DraughtsStorage.list()).map((r) => r.id), ['second']);
  });

  test(
    'AI save restores side, level, history and complete-turn undo',
    () async {
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.english),
      );
      session.applyMove(session.legalMoves().first);
      final afterHuman = session.position.signature(session.turn);
      session.applyMove(session.legalMoves().first);
      await DraughtsStorage.save(
        DraughtsRecord.fromSession(
          session,
          id: 'ai-game',
          kind: DraughtsGameKind.ai,
          localSide: Side.black,
          aiLevel: DraughtsAiLevel.advanced,
        ),
      );
      final record = (await DraughtsStorage.list()).single;
      expect(record.kind, DraughtsGameKind.ai);
      expect(record.localSide, Side.black);
      expect(record.aiLevel, DraughtsAiLevel.advanced);
      final restored = DraughtsSession.fromJson(record.sessionState);
      expect(restored.undo(), isTrue);
      expect(restored.position.signature(restored.turn), afterHuman);
      expect(restored.undo(), isTrue);
      expect(restored.moves, isEmpty);
    },
  );

  test('record storage preserves session state and game result', () async {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
    );
    expect(session.applyMove(session.legalMoves().first), isTrue);
    expect(session.resign(Side.white), isTrue);
    final record = DraughtsRecord.fromSession(
      session,
      id: 'saved-game',
      kind: DraughtsGameKind.online,
      localSide: Side.black,
    );

    await DraughtsStorage.save(record);
    final saved = (await DraughtsStorage.list()).single;
    final restored = DraughtsSession.fromJson(saved.sessionState);

    expect(saved.kind, DraughtsGameKind.online);
    expect(saved.localSide, Side.black);
    expect(saved.result, '1-0');
    expect(restored.result?.reason, DraughtsEndReason.resignation);
    expect(restored.result?.winner, Side.black);
    expect(restored.moves, session.moves);
    await DraughtsStorage.delete('saved-game');
    expect(await DraughtsStorage.list(), isEmpty);
  });
}
