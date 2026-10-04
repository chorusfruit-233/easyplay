import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'rules_test.dart' show fixture, red, black, play;

// Adjudicator tests separate the supplied, independently classified move flags
// from rule-level chase geometry. Actual legal long-check/chase cycles are in rules_test.
List<XiangqiMoveRecord> cycle({
  required List<bool> checks,
  required List<Set<int>> chases,
  int? captureAt,
}) {
  final s = XiangqiSession();
  play(s, 'b0a2 b9a7 a2b0 a7b9 b0a2 b9a7 a2b0 a7b9');
  return [
    for (var i = 0; i < s.repetitionHistory.length; i++)
      XiangqiMoveRecord(
        before: s.repetitionHistory[i].before,
        after: s.repetitionHistory[i].after,
        move: s.repetitionHistory[i].move,
        piece: s.repetitionHistory[i].piece,
        captured: i == captureAt ? black(XiangqiPieceType.horse) : null,
        gaveCheck: checks[i % 4],
        chasedIds: chases[i % 4],
      ),
  ];
}

XiangqiRepetitionResult? judge(
  List<bool> checks,
  List<Set<int>> chases, {
  int? captureAt,
}) {
  final history = cycle(checks: checks, chases: chases, captureAt: captureAt);
  return XiangqiRepetition().evaluate(history.last.after, history);
}

void main() {
  test(
    'a legal mixed check and quiet cycle is allowed in the Asian profile',
    () {
      final session = XiangqiSession(
        position: parseXiangqiFen('4k4/3R5/9/9/9/4P4/9/9/9/4K4 w - - 0 1'),
      );
      const moves = 'd8e8 e9d9 e8e7 d9d8 e7d7 d8e8 d7d8 e8e9';
      play(session, '$moves $moves');
      expect(session.result!.reason, XiangqiEndReason.repetitionDraw);
    },
  );
  test(
    'both perpetual checks draw',
    () => expect(
      judge([true, true, true, true], [{}, {}, {}, {}])!.isDraw,
      isTrue,
    ),
  );
  test(
    'both perpetual chases draw',
    () => expect(
      judge(
        [false, false, false, false],
        [
          {1},
          {2},
          {1},
          {2},
        ],
      )!.isDraw,
      isTrue,
    ),
  );
  test(
    'one check versus other chase penalizes the checking side',
    () => expect(
      judge(
        [true, false, true, false],
        [
          {},
          {2},
          {},
          {2},
        ],
      )!.offender,
      XiangqiSide.red,
    ),
  );
  test(
    'checking and chasing mixed on alternate turns is allowed by pinned Asian profile',
    () => expect(
      judge(
        [true, false, false, false],
        [
          {},
          {},
          {1},
          {},
        ],
      )!.isDraw,
      isTrue,
    ),
  );
  test(
    'switching chased victims does not constitute perpetual chase',
    () => expect(
      judge(
        [false, false, false, false],
        [
          {1},
          {},
          {2},
          {},
        ],
      )!.isDraw,
      isTrue,
    ),
  );
  test(
    'capture prevents repetition adjudication across that boundary',
    () => expect(
      judge(
        [false, false, false, false],
        [
          {1},
          {},
          {1},
          {},
        ],
        captureAt: 4,
      ),
      isNull,
    ),
  );
  test('kings, soldiers and unadvanced enemy soldiers are exempt chases', () {
    final king = fixture({const Cell(8, 3): black(XiangqiPieceType.chariot)});
    expect(XiangqiRepetition.chased(king, XiangqiSide.red), isEmpty);
    final soldier = fixture({
      const Cell(4, 2): red(XiangqiPieceType.soldier),
      const Cell(4, 3): black(XiangqiPieceType.horse),
    });
    expect(XiangqiRepetition.chased(soldier, XiangqiSide.red), isEmpty);
    final pawnTarget = fixture({
      const Cell(4, 0): red(XiangqiPieceType.chariot),
      const Cell(3, 0): black(XiangqiPieceType.soldier),
    });
    expect(XiangqiRepetition.chased(pawnTarget, XiangqiSide.red), isEmpty);
  });
  test('legal recapture and symmetric rook attacks exempt victims', () {
    final protected = fixture({
      const Cell(4, 0): red(XiangqiPieceType.chariot),
      const Cell(4, 3): black(XiangqiPieceType.horse),
      const Cell(2, 3): black(XiangqiPieceType.chariot),
    });
    expect(XiangqiRepetition.chased(protected, XiangqiSide.red), isEmpty);
    final symmetric = fixture({
      const Cell(4, 0): red(XiangqiPieceType.chariot),
      const Cell(4, 3): black(XiangqiPieceType.chariot),
    });
    expect(XiangqiRepetition.chased(symmetric, XiangqiSide.red), isEmpty);
  });
  test('horse pursuing a protected stronger rook remains a chase', () {
    final p = fixture({
      const Cell(5, 1): red(XiangqiPieceType.horse),
      const Cell(3, 2): black(XiangqiPieceType.chariot),
      const Cell(3, 0): black(XiangqiPieceType.chariot),
    });
    expect(
      XiangqiRepetition.chased(p, XiangqiSide.red),
      contains(p.pieceAt(const Cell(3, 2))!.id),
    );
  });
}
