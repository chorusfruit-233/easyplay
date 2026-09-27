import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trimmed but structurally faithful `kata-analyze` output: two `info` sections
/// and a `rootInfo` section, in the documented field order.
const _sample = '''
info move E4 visits 487 utility -0.0408357 winrate 0.480018 scoreMean -0.611848 scoreStdev 24.7058 scoreLead -0.611848 scoreSelfplay -0.515178 prior 0.221121 lcb 0.477221 utilityLcb -0.0486664 order 0 pv E4 E3 F3 D3 F4 info move P16 visits 470 utility -0.0414945 winrate 0.479712 scoreMean -0.63075 scoreStdev 24.7179 scoreLead -0.63075 scoreSelfplay -0.5221 prior 0.220566 lcb 0.47657 utilityLcb -0.0502929 order 1 pv P16 P17 O17 Q17 O16 rootInfo visits 1101 winrate 0.4799 scoreLead -0.62
''';

void main() {
  test('parses candidate moves with their statistics', () {
    final analysis = parseKataGoAnalysis(_sample, boardSize: 19);

    expect(analysis.moves, hasLength(2));
    final first = analysis.moves.first;
    expect(first.vertex, 'E4');
    expect(first.visits, 487);
    expect(first.winRate, closeTo(0.480018, 1e-6));
    expect(first.scoreLead, closeTo(-0.611848, 1e-6));
    expect(first.prior, closeTo(0.221121, 1e-6));
    expect(first.order, 0);

    final second = analysis.moves[1];
    expect(second.vertex, 'P16');
    expect(second.order, 1);
  });

  test('a pv ends at the next section, not at a fixed length', () {
    final analysis = parseKataGoAnalysis(_sample, boardSize: 19);
    // The first pv must stop before the second `info`, and the second pv must
    // stop before `rootInfo` rather than swallowing it.
    expect(analysis.moves[0].pv, ['E4', 'E3', 'F3', 'D3', 'F4']);
    expect(analysis.moves[1].pv, ['P16', 'P17', 'O17', 'Q17', 'O16']);
  });

  test('reads the root section, which is separate from the candidates', () {
    final analysis = parseKataGoAnalysis(_sample, boardSize: 19);
    expect(analysis.rootVisits, 1101);
    expect(analysis.rootWinRate, closeTo(0.4799, 1e-6));
    expect(analysis.rootScoreLead, closeTo(-0.62, 1e-6));
  });

  test('candidates are ordered by their reported order field', () {
    final reversed = '''
info move P16 visits 5 order 1 pv P16 info move E4 visits 9 order 0 pv E4
''';
    final analysis = parseKataGoAnalysis(reversed, boardSize: 19);
    expect(analysis.moves.map((m) => m.vertex).toList(), ['E4', 'P16']);
  });

  test('share of visits is relative to the root total', () {
    final analysis = parseKataGoAnalysis(_sample, boardSize: 19);
    expect(
      analysis.moves[0].shareOf(analysis.rootVisits),
      closeTo(487 / 1101, 1e-9),
    );
    // A zero root must not divide by zero.
    expect(analysis.moves[0].shareOf(0), 0);
  });

  test('ownership is accepted only when it covers the whole board', () {
    final full = List.generate(361, (i) => (i % 3) - 1).join(' ');
    final parsed = parseKataGoAnalysis(
      '$full rootInfo visits 10 winrate 0.5 scoreLead 0 ownership $full',
      boardSize: 19,
    );
    expect(parsed.ownership, hasLength(361));

    // A short list is a partial or malformed report; better to show nothing
    // than to colour the board from the wrong points.
    final short = parseKataGoAnalysis(
      'rootInfo visits 10 ownership 0.1 0.2 0.3',
      boardSize: 19,
    );
    expect(short.ownership, isNull);
  });

  test('unknown fields are skipped rather than failing the parse', () {
    // KataGo documents that new fields may appear; a newer engine must not
    // break the review panel.
    final future = '''
info move E4 visits 10 winrate 0.5 scoreLead 0 order 0 somethingNew 42 pv E4 rootInfo visits 10 winrate 0.5 scoreLead 0 brandNewField abc
''';
    final analysis = parseKataGoAnalysis(future, boardSize: 19);
    expect(analysis.moves.single.vertex, 'E4');
    expect(analysis.moves.single.visits, 10);
    expect(analysis.rootVisits, 10);
  });

  test('an empty response yields an empty analysis, not an exception', () {
    final analysis = parseKataGoAnalysis('', boardSize: 19);
    expect(analysis.isEmpty, isTrue);
    expect(analysis.rootVisits, 0);
  });

  test('White-perspective numbers are flipped into Black\'s frame', () {
    // KataGo reports from the side named in the command, so a review table that
    // always means "Black" has to convert rather than relabel.
    final white = parseKataGoAnalysis(
      'info move E4 visits 10 winrate 0.25 scoreLead 3.5 order 0 pv E4 '
      'rootInfo visits 10 winrate 0.25 scoreLead 3.5 ownership 0.5 -0.5',
      boardSize: 19,
      perspective: Side.white,
    );
    expect(white.moves.single.winRate, closeTo(0.75, 1e-9));
    expect(white.moves.single.scoreLead, closeTo(-3.5, 1e-9));
    expect(white.rootWinRate, closeTo(0.75, 1e-9));
    expect(white.rootScoreLead, closeTo(-3.5, 1e-9));
    // The sample ownership is too short to keep, so only the sign convention
    // shown above is observable through the public API here.
    expect(white.ownership, isNull);

    final black = parseKataGoAnalysis(
      'info move E4 visits 10 winrate 0.25 scoreLead 3.5 order 0 pv E4',
      boardSize: 19,
    );
    expect(black.moves.single.winRate, closeTo(0.25, 1e-9));
    expect(black.moves.single.scoreLead, closeTo(3.5, 1e-9));
  });

  test('ownership is mirrored for White so positive always means Black', () {
    final values = List.generate(361, (i) => i.isEven ? 0.4 : -0.4);
    final analysis = parseKataGoAnalysis(
      'rootInfo visits 10 winrate 0.4 scoreLead 1 ownership '
      '${values.join(' ')}',
      boardSize: 19,
      perspective: Side.white,
    );
    expect(analysis.ownership, isNotNull);
    expect(analysis.ownership!.first, closeTo(-0.4, 1e-9));
    expect(analysis.ownership![1], closeTo(0.4, 1e-9));
  });

  test('vertex conversion round-trips and skips the letter I', () {
    // GTP columns skip I, so column 8 is J and not I.
    // Model row 0 is the top of the board (this is how SGF coordinates are
    // decoded elsewhere in the project), while GTP counts rows from the bottom.
    expect(gtpVertex(const Cell(0, 0), boardSize: 19), 'A19');
    expect(gtpVertex(const Cell(18, 0), boardSize: 19), 'A1');
    expect(gtpVertex(const Cell(0, 8), boardSize: 19), 'J19');
    // Q16 is the standard first move in a 19x19 SGF, which is model (3, 15).
    expect(gtpVertex(const Cell(3, 15), boardSize: 19), 'Q16');

    for (final cell in [
      const Cell(0, 0),
      const Cell(3, 3),
      const Cell(18, 18),
      const Cell(9, 8),
    ]) {
      expect(
        cellFromGtpVertex(gtpVertex(cell, boardSize: 19), boardSize: 19),
        cell,
        reason: '${gtpVertex(cell, boardSize: 19)} 应还原回原坐标',
      );
    }
  });

  test('pass and malformed vertices do not become coordinates', () {
    for (final vertex in ['pass', 'PASS', '', 'Z9', 'A0', 'A20', 'I5']) {
      final cell = cellFromGtpVertex(vertex, boardSize: 19);
      if (vertex.toUpperCase() == 'I5') {
        // I is a legal-looking letter but not a GTP column; indexOf returns -1.
        expect(cell, isNull, reason: '$vertex 不是有效列');
      } else {
        expect(cell, isNull, reason: '$vertex 不应产生坐标');
      }
    }
  });
}
