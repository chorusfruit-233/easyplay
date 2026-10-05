import '../doudizhu_model.dart';
import '../doudizhu_rules.dart';

/// Enumerates rank combinations, choosing canonical physical cards per rank.
/// Suit is irrelevant to legal play; no exponential 2^20 subset search.
class LegalPlayGenerator {
  const LegalPlayGenerator();
  List<List<int>> generate(List<PlayingCard> hand, TrickState trick) {
    final groups = <int, List<int>>{};
    for (final c in hand) {
      (groups[c.rank] ??= []).add(c.id);
    }
    final ranks = groups.keys.toList()..sort();
    final previous = classifyPlay(trick.cardIds.map(PlayingCard.new).toList());
    final result = <List<int>>[];
    final seen = <String>{};
    void add(Map<int, int> counts) {
      if (counts.entries.any((e) => (groups[e.key]?.length ?? 0) < e.value)) {
        return;
      }
      final ids = [
        for (final e in counts.entries) ...groups[e.key]!.take(e.value),
      ]..sort();
      final p = classifyPlay(ids.map(PlayingCard.new).toList());
      if (p != null &&
          (previous == null || canBeat(p, previous)) &&
          seen.add(ids.join(','))) {
        result.add(ids);
      }
    }

    void attachments(
      Map<int, int> body,
      int number,
      int each, {
      bool repeat = false,
    }) {
      final available = ranks
          .where((r) => !body.containsKey(r) && groups[r]!.length >= each)
          .toList();
      void visit(int index, int left, Map<int, int> selected) {
        if (left == 0) {
          add({...body, ...selected});
          return;
        }
        for (var i = index; i < available.length; i++) {
          final rank = available[i];
          final maxCount = repeat
              ? (groups[rank]!.length < left ? groups[rank]!.length : left)
              : 1;
          for (var count = 1; count <= maxCount; count++) {
            selected[rank] = count * each;
            visit(i + 1, left - count, selected);
          }
          selected.remove(rank);
        }
      }

      visit(0, number, {});
    }

    for (final r in ranks) {
      for (var n = 1; n <= groups[r]!.length; n++) {
        add({r: n});
      }
      if (groups[r]!.length >= 3) {
        attachments({r: 3}, 1, 1);
        attachments({r: 3}, 1, 2);
      }
      if (groups[r]!.length == 4) {
        attachments({r: 4}, 2, 1, repeat: true);
        attachments({r: 4}, 2, 2);
      }
    }
    add({16: 1, 17: 1});
    for (final each in [1, 2, 3]) {
      final min = each == 1
          ? 5
          : each == 2
          ? 3
          : 2;
      for (var start = 3; start <= 14; start++) {
        final body = <int, int>{};
        for (var end = start; end <= 14; end++) {
          if ((groups[end]?.length ?? 0) < each) break;
          body[end] = each;
          if (body.length < min) continue;
          add(body);
          if (each == 3) {
            attachments(body, body.length, 1);
            attachments(body, body.length, 2);
          }
        }
      }
    }
    return result;
  }
}

List<CardPlay> legalPlays(
  List<PlayingCard> hand,
  TrickState trick, {
  PlayerSeat seat = PlayerSeat.seat0,
}) => const LegalPlayGenerator()
    .generate(hand, trick)
    .map((ids) => CardPlay(seat, ids))
    .toList();
