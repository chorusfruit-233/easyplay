import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/game_session.dart' show Side;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
