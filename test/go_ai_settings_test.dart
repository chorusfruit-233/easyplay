import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_ai_settings.dart';

void main() {
  test('AI game choices serialize and preserve the selected side and rank', () {
    const settings = GoAiSettings(
      playerColor: GoPlayerColor.white,
      rank: GoAiRank.d1,
      style: GoAiStyle.traditional,
    );
    final restored = GoAiSettings.fromJson(settings.toJson());
    expect(restored.playerColor, GoPlayerColor.white);
    expect(restored.rank.maxVisits, 120);
    expect(restored.style.label, '传统');
    expect(restored.resolvePlayerSide(), Side.white);
  });

  // Rank-dependent tuning lives in the engine's override rules; the built-in
  // baseline stays flat so a phone does not end up thinking for minutes, and
  // Max is the single deliberate exception.
  test('only Max raises the baseline search budget', () {
    final normal = GoAiRank.values
        .where((rank) => rank != GoAiRank.strongest)
        .map((rank) => rank.maxVisits)
        .toSet();
    expect(normal, {120});
    expect(GoAiRank.strongest.maxVisits, greaterThan(120));
  });

  // The rank enum went from seven presets to the full 20k..9d scale, which
  // renamed every member. Stored names must still resolve to the same rank
  // instead of silently collapsing to the fallback.
  test('legacy rank names restore to the equivalent rank', () {
    const expected = {
      'beginner': GoAiRank.k20,
      'club': GoAiRank.k10,
      'intermediate': GoAiRank.k5,
      'advanced': GoAiRank.k1,
      'dan1': GoAiRank.d1,
      'dan5': GoAiRank.d5,
      'strongest': GoAiRank.strongest,
    };
    for (final entry in expected.entries) {
      final restored = GoAiSettings.fromJson({'rank': entry.key});
      expect(restored.rank, entry.value, reason: '旧名 ${entry.key}');
    }
    // Unknown names still fall back rather than throwing.
    expect(GoAiSettings.fromJson({'rank': 'nonsense'}).rank, GoAiRank.k5);
  });

  test('legacy non-KataGo modes restore as local play', () {
    final restored = GoAiSettings.fromJson({'opponentMode': 'basic'});
    expect(restored.opponentMode, GoOpponentMode.local);
  });

  test('human style settings roundtrip rank and model fields', () {
    const settings = GoAiSettings(
      style: GoAiStyle.human,
      humanModelId: 'human-model',
      humanStyleRank: -5,
      humanSLProfile: 'human_5d_6d',
    );
    final restored = GoAiSettings.fromJson(settings.toJson());
    expect(restored.usesHumanStyle, isTrue);
    expect(restored.resolvedHumanStyleRank, -5);
    expect(restored.humanModelId, 'human-model');
    expect(restored.humanSLProfile, 'human_5d_6d');
  });
}
