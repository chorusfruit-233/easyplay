import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_ai_settings.dart';

void main() {
  test('AI game choices serialize and preserve the selected side and rank', () {
    const settings = GoAiSettings(
      playerColor: GoPlayerColor.white,
      rank: GoAiRank.dan1,
      style: GoAiStyle.traditional,
    );
    final restored = GoAiSettings.fromJson(settings.toJson());
    expect(restored.playerColor, GoPlayerColor.white);
    expect(restored.rank.maxVisits, 2500);
    expect(restored.style.label, '传统');
    expect(restored.resolvePlayerSide(), Side.white);
  });

  test('rank presets map to increasing KataGo search budgets', () {
    final visits = GoAiRank.values.map((rank) => rank.maxVisits).toList();
    expect(visits, orderedEquals([...visits]..sort()));
    expect(GoAiRank.intermediate.maxVisits, 500);
  });

  test('legacy non-KataGo modes restore as local play', () {
    final restored = GoAiSettings.fromJson({'opponentMode': 'basic'});
    expect(restored.opponentMode, GoOpponentMode.local);
  });
}
