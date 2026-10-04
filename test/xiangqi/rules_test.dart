import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:flutter_test/flutter_test.dart';

XiangqiPosition fixture(
  Map<Cell, XiangqiPiece> pieces, {
  XiangqiSide turn = XiangqiSide.red,
}) {
  final board = List.generate(10, (_) => List<XiangqiPiece?>.filled(9, null));
  board[0][4] = const XiangqiPiece(XiangqiSide.black, XiangqiPieceType.general);
  board[9][4] = const XiangqiPiece(XiangqiSide.red, XiangqiPieceType.general);
  board[5][4] = const XiangqiPiece(XiangqiSide.red, XiangqiPieceType.soldier);
  for (final entry in pieces.entries) {
    board[entry.key.row][entry.key.col] = entry.value;
  }
  return XiangqiPosition(board: board, sideToMove: turn);
}

XiangqiPiece red(XiangqiPieceType type) => XiangqiPiece(XiangqiSide.red, type);
XiangqiPiece black(XiangqiPieceType type) =>
    XiangqiPiece(XiangqiSide.black, type);
bool can(XiangqiPosition p, String move) =>
    XiangqiMoveGenerator.legalMoves(p).contains(parseXiangqiUciMove(move));
void play(XiangqiSession session, String moves) {
  for (final text in moves.split(' ')) {
    expect(session.applyMove(parseXiangqiUciMove(text)), isTrue, reason: text);
  }
}

void main() {
  test('32 pieces, red first, immutable board and strict structural input', () {
    final p = XiangqiPosition.initial();
    expect(
      p.board.expand((row) => row).whereType<XiangqiPiece>(),
      hasLength(32),
    );
    expect(p.sideToMove, XiangqiSide.red);
    expect(p.pieceAt(const Cell(9, 4))!.label, '帅');
    expect(p.pieceAt(const Cell(0, 4))!.label, '将');
    expect(() => p.board[0][0] = null, throwsUnsupportedError);
    expect(() => XiangqiPosition(board: []), throwsFormatException);
    final rows = p.board.map((r) => r.toList()).toList()..[0][4] = null;
    expect(() => XiangqiPosition(board: rows), throwsFormatException);
  });
  test('FEN and all UCI coordinates round trip, no chess promotion grammar', () {
    final p = XiangqiPosition.initial();
    const fen =
        'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';
    expect(exportXiangqiFen(p), fen);
    expect(exportXiangqiFen(parseXiangqiFen(fen)), fen);
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 9; c++) {
        final cell = Cell(r, c);
        expect(parseXiangqiSquare(xiangqiSquare(cell)), cell);
      }
    }
    expect(parseXiangqiUciMove('a0i9').to, const Cell(0, 8));
    for (final value in ['a0a0', 'a0j9', 'a0i9q', 'a1a10', 'e2e4n']) {
      expect(() => parseXiangqiUciMove(value), throwsFormatException);
    }
    for (final value in [
      fen.replaceFirst('w - -', 'w K -'),
      fen.replaceFirst('rnbakabnr', 'rnbakabn'),
      fen.replaceFirst('w - - 0 1', 'w - - -1 1'),
    ]) {
      expect(() => parseXiangqiFen(value), throwsFormatException);
    }
  });
  test('initial perft verified against official 4c17cee native engine', () {
    final p = XiangqiPosition.initial();
    expect(xiangqiPerft(p, 1), 44);
    expect(xiangqiPerft(p, 2), 1920);
    expect(xiangqiPerft(p, 3), 79666);
  });
  test('horse leg blocks only corresponding jumps', () {
    final p = fixture({
      const Cell(9, 1): red(XiangqiPieceType.horse),
      const Cell(8, 1): red(XiangqiPieceType.chariot),
    });
    expect(can(p, 'b0a2'), isFalse);
    expect(can(p, 'b0c2'), isFalse);
    expect(can(p, 'b0d1'), isTrue);
  });
  test('elephant eye, river and advisor palace', () {
    final p = fixture({
      const Cell(9, 2): red(XiangqiPieceType.elephant),
      const Cell(8, 1): red(XiangqiPieceType.chariot),
      const Cell(9, 3): red(XiangqiPieceType.advisor),
    });
    expect(can(p, 'c0a2'), isFalse);
    expect(can(p, 'c0e2'), isTrue);
    expect(can(p, 'd0e1'), isTrue);
    expect(can(p, 'd0c1'), isFalse);
    final q = fixture({const Cell(5, 2): red(XiangqiPieceType.elephant)});
    expect(can(q, 'c4e6'), isFalse);
  });
  test(
    'cannon needs zero screens for movement and exactly one for capture',
    () {
      final p = fixture({
        const Cell(7, 1): red(XiangqiPieceType.cannon),
        const Cell(5, 1): red(XiangqiPieceType.chariot),
        const Cell(3, 1): black(XiangqiPieceType.chariot),
      });
      expect(can(p, 'b2b3'), isTrue);
      expect(can(p, 'b2b5'), isFalse);
      expect(can(p, 'b2b6'), isTrue);
      final q = fixture({
        const Cell(7, 1): red(XiangqiPieceType.cannon),
        const Cell(3, 1): black(XiangqiPieceType.chariot),
      });
      expect(can(q, 'b2b6'), isFalse);
    },
  );
  test('soldiers cannot retreat, only cross river to move sideways', () {
    final p = fixture({
      const Cell(6, 0): red(XiangqiPieceType.soldier),
      const Cell(4, 2): red(XiangqiPieceType.soldier),
    });
    expect(can(p, 'a3a4'), isTrue);
    expect(can(p, 'a3b3'), isFalse);
    expect(can(p, 'a3a2'), isFalse);
    expect(can(p, 'c5b5'), isTrue);
    expect(can(p, 'c5c4'), isFalse);
    final q = fixture({
      const Cell(5, 6): black(XiangqiPieceType.soldier),
    }, turn: XiangqiSide.black);
    expect(can(q, 'g4h4'), isTrue);
    expect(can(q, 'g4g3'), isTrue);
    expect(can(q, 'g4g5'), isFalse);
  });
  test('flying generals, own check and check response are enforced', () {
    final p = fixture({const Cell(5, 4): red(XiangqiPieceType.chariot)});
    expect(can(p, 'e4d4'), isFalse);
    expect(can(p, 'e4e5'), isTrue);
    expect(can(p, 'e0f0'), isTrue);
    final checked = fixture({
      const Cell(8, 0): black(XiangqiPieceType.chariot),
    });
    expect(XiangqiMoveGenerator.isInCheck(checked, XiangqiSide.red), isFalse);
    final q = fixture({const Cell(9, 0): black(XiangqiPieceType.chariot)});
    expect(XiangqiMoveGenerator.isInCheck(q, XiangqiSide.red), isTrue);
    expect(can(q, 'e0e1'), isTrue);
    expect(can(q, 'e0d0'), isFalse);
  });
  test(
    'checkmate and nonchecking confinement both lose, never king capture',
    () {
      final mate = XiangqiSession(
        position: parseXiangqiFen('R3k4/4R4/9/5N3/9/4P4/9/9/9/4K4 b - - 0 1'),
      );
      expect(mate.result!.reason, XiangqiEndReason.checkmate);
      expect(mate.result!.winner, XiangqiSide.red);
      final stuck = XiangqiSession(
        position: parseXiangqiFen('4k4/3R1R3/9/9/9/4P4/9/9/9/4K4 b - - 0 1'),
      );
      expect(stuck.result!.reason, XiangqiEndReason.noLegalMove);
      expect(stuck.result!.winner, XiangqiSide.red);
      expect(mate.applyMove(parseXiangqiUciMove('e9e8')), isFalse);
    },
  );
  test('single perpetual check loses and undo fully restores its history', () {
    final s = XiangqiSession(
      position: parseXiangqiFen('4k4/3R5/9/9/9/4P4/9/9/9/4K4 w - - 0 1'),
    );
    const cycle = 'd8e8 e9d9 e8d8 d9e9';
    play(s, '$cycle $cycle');
    expect(s.result!.reason, XiangqiEndReason.repetitionViolation);
    expect(s.result!.winner, XiangqiSide.black);
    expect(
      s.repetitionHistory
          .where((r) => r.side == XiangqiSide.red)
          .every((r) => r.gaveCheck),
      isTrue,
    );
    expect(s.undo(), isTrue);
    expect(s.gameOver, isFalse);
    expect(s.moves, hasLength(7));
    expect(s.noCapturePlies, 7);
    play(s, 'd9e9');
    expect(s.result!.winner, XiangqiSide.black);
  });
  test(
    'single perpetual chase loses; the same victim identity follows moves',
    () {
      final s = XiangqiSession(
        position: parseXiangqiFen('4k4/9/9/9/9/3nP4/1R7/9/9/4K4 w - - 0 1'),
      );
      const cycle = 'b3d3 d4b5 d3b3 b5d4';
      play(s, '$cycle $cycle');
      expect(s.result!.reason, XiangqiEndReason.repetitionViolation);
      expect(s.result!.winner, XiangqiSide.black);
      final ids = s.repetitionHistory
          .where((r) => r.side == XiangqiSide.red)
          .map((r) => r.chasedIds.single)
          .toSet();
      expect(ids, hasLength(1));
    },
  );
  test('unforced repetition draws, not all repetitions are losses', () {
    final s = XiangqiSession();
    const cycle = 'b0a2 b9a7 a2b0 a7b9';
    play(s, '$cycle $cycle');
    expect(s.result!.reason, XiangqiEndReason.repetitionDraw);
    expect(s.result!.winner, isNull);
    expect(s.fork().result, s.result);
    s.reset();
    expect(s.moves, isEmpty);
    expect(s.repetitionHistory, isEmpty);
    expect(s.gameOver, isFalse);
  });
  test('no capture clock draws at 120 plies, undo and capture restore it', () {
    final s = XiangqiSession(
      position: parseXiangqiFen('r3k4/9/9/9/9/4P4/9/9/9/R3K4 w - - 119 1'),
    );
    play(s, 'a0a1');
    expect(s.result!.reason, XiangqiEndReason.moveLimitDraw);
    s.undo();
    expect(s.gameOver, isFalse);
    expect(s.noCapturePlies, 119);
    play(s, 'a0a9');
    expect(s.noCapturePlies, 0);
    expect(s.gameOver, isFalse);
    s.undo();
    expect(s.noCapturePlies, 119);
  });
}
