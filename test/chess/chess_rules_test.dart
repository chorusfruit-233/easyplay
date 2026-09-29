import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/chess/chess.dart';

ChessSession fen(String text) => ChessSession(position: parseFen(text));
void play(ChessSession s, String line) {
  for (final move in line.split(' ')) {
    expect(
      s.applyMove(parseUciMove(move)),
      isTrue,
      reason: '$move in ${s.fen}',
    );
  }
}

Set<String> moves(ChessSession s) => s.legalMoves().map(moveToUci).toSet();

void main() {
  test('initial position, immutable board and FEN/UCI roundtrips', () {
    final s = ChessSession();
    expect(s.fen, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
    expect(exportFen(parseFen(s.fen)), s.fen);
    expect(() => s.position.board[0][0] = null, throwsUnsupportedError);
    for (final text in ['e2e4', 'e1g1', 'a7b8q', 'a7a8r', 'b7b8b', 'h2h1n']) {
      expect(moveToUci(parseUciMove(text)), text);
    }
    for (final text in ['e2e9', 'e7e8k', 'a0a1', '0000', 'e2e4 junk']) {
      expect(() => parseUciMove(text), throwsFormatException);
    }
    for (final text in [
      '',
      '8/8/8/8/8/8/8/8 w - - 0 1',
      '4k3/8/8/8/8/8/8/4K3 x - - 0 1',
      '4k3/8/8/8/8/8/8/4K3 w KK - 0 1',
    ]) {
      expect(() => parseFen(text), throwsFormatException);
    }
  });
  test('initial perft depths 1 through 4', () {
    for (var depth = 1; depth <= 4; depth++) {
      expect(
        perft(ChessPosition.initial(), depth),
        [20, 400, 8902, 197281][depth - 1],
      );
    }
  });
  test('Kiwipete perft exercises castling, pins and checks', () {
    final p = parseFen(
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
    );
    for (var depth = 1; depth <= 3; depth++) {
      expect(perft(p, depth), [48, 2039, 97862][depth - 1]);
    }
  });
  test('classic endgame, promotion and check perft positions', () {
    final cases = {
      '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1': [14, 191, 2812, 43238],
      'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1': [
        6,
        264,
        9467,
      ],
      'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8': [
        44,
        1486,
        62379,
      ],
    };
    for (final entry in cases.entries) {
      for (var depth = 1; depth <= entry.value.length; depth++) {
        expect(
          perft(parseFen(entry.key), depth),
          entry.value[depth - 1],
          reason: entry.key,
        );
      }
    }
  });
  test('castling moves both pieces and undo restores all rights', () {
    for (final uci in ['e1g1', 'e1c1']) {
      final s = fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      final before = s.fen;
      play(s, uci);
      expect(s.position.castlingRights.whiteKing, false);
      expect(s.position.castlingRights.whiteQueen, false);
      expect(
        s.position.pieceAt(parseChessSquare(uci == 'e1g1' ? 'f1' : 'd1'))?.type,
        ChessPieceType.rook,
      );
      expect(s.undo(), true);
      expect(s.fen, before);
    }
    final s = fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
    play(s, 'h1h2 h8h7 h2h1 h7h8');
    expect(moves(s), isNot(contains('e1g1')));
    expect(s.position.castlingRights.blackKing, false);
    play(s, 'e1e2 e8e7 e2e1 e7e8');
    expect(s.position.castlingRights.fen, '-');
  });
  test(
    'castling cannot cross check, start in check or cross an occupied path',
    () {
      for (final f in [
        '4kr2/8/8/8/8/8/8/4K2R w K - 0 1',
        '4k1r1/8/8/8/8/8/8/4K2R w K - 0 1',
        'k3r3/8/8/8/8/8/8/4K2R w K - 0 1',
        '4k3/8/8/8/8/8/8/4KN1R w K - 0 1',
      ]) {
        expect(moves(fen(f)), isNot(contains('e1g1')));
      }
      final s = fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      play(s, 'a1a8');
      expect(s.position.castlingRights.blackQueen, false);
      expect(s.position.castlingRights.whiteQueen, false);
    },
  );
  test('en passant removes the captured pawn, expires and undoes exactly', () {
    final s = ChessSession();
    play(s, 'e2e4 a7a6 e4e5 d7d5');
    final before = s.fen;
    expect(moves(s), contains('e5d6'));
    play(s, 'e5d6');
    expect(s.position.pieceAt(parseChessSquare('d5')), null);
    expect(s.position.halfmoveClock, 0);
    s.undo();
    expect(s.fen, before);
    play(s, 'g1f3 a6a5');
    expect(moves(s), isNot(contains('e5d6')));
    final pinned = fen('8/8/8/r4pPK/8/8/8/4k3 w - f6 0 1');
    expect(moves(pinned), isNot(contains('g5f6')));
    expect(ChessSession.positionKey(pinned.position), endsWith(' -'));
  });
  test('all four promotions including captures, no implicit promotion', () {
    for (final suffix in ['q', 'r', 'b', 'n']) {
      for (final move in ['a7a8$suffix', 'a7b8$suffix']) {
        final s = fen('1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1');
        expect(s.applyMove(parseUciMove('a7a8')), false);
        play(s, move);
        expect(
          s.position.pieceAt(parseUciMove(move).to)?.fen.toLowerCase(),
          suffix,
        );
        s.undo();
        expect(
          s.position.pieceAt(parseChessSquare('a7'))?.type,
          ChessPieceType.pawn,
        );
      }
    }
  });
  test('pins, double check, blocking, capturing checker, king safety', () {
    final pin = fen('k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1');
    expect(moves(pin), isNot(contains('e2f2')));
    expect(moves(pin), contains('e2e8'));
    final doubleCheck = fen('k3r3/8/8/8/1b6/8/8/3QK3 w - - 0 1');
    expect(doubleCheck.isInCheck(Side.white), true);
    expect(
      doubleCheck.legalMoves().every((m) => m.from == parseChessSquare('e1')),
      true,
    );
    final block = fen('k3r3/8/8/8/8/8/3B4/4K3 w - - 0 1');
    expect(moves(block), contains('d2e3'));
    expect(moves(block), contains('e1d1'));
    expect(moves(block), isNot(contains('e1e2')));
  });
  test('checkmate and stalemate, mate takes priority over 75 move rule', () {
    final s = ChessSession();
    play(s, 'f2f3 e7e5 g2g4 d8h4');
    expect(
      s.result,
      const ChessResult(winner: Side.black, reason: ChessEndReason.checkmate),
    );
    expect(
      fen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1').result?.reason,
      ChessEndReason.stalemate,
    );
    final mate = fen('7k/8/5KQ1/8/8/8/8/8 w - - 149 1');
    play(mate, 'g6g7');
    expect(mate.result?.reason, ChessEndReason.checkmate);
  });
  test(
    'threefold is claimable, fivefold is automatic; undo restores counts',
    () {
      final s = ChessSession();
      const cycle = 'g1f3 g8f6 f3g1 f6g8';
      play(s, '$cycle $cycle');
      expect(s.gameOver, false);
      expect(s.repetitionCount, 3);
      expect(s.claimableDraw(), ChessEndReason.threefoldRepetition);
      expect(s.claimDraw(), true);
      s.undo();
      expect(s.result, null);
      expect(s.repetitionCount, 3);
      s.undo();
      expect(s.repetitionCount, 2);
      expect(
        s.claimableDraw(parseUciMove('f6g8')),
        ChessEndReason.threefoldRepetition,
      );
      play(s, 'f6g8 $cycle $cycle');
      expect(s.result?.reason, ChessEndReason.fivefoldRepetition);
    },
  );
  test('50 and 75 move rules and reset of halfmove clock', () {
    final s = fen('4k2r/8/8/8/8/8/8/R3K3 w - - 99 1');
    expect(s.claimableDraw(parseUciMove('a1a2')), ChessEndReason.fiftyMoveRule);
    play(s, 'a1a2');
    expect(s.claimDraw(), true);
    expect(s.result?.reason, ChessEndReason.fiftyMoveRule);
    final auto = fen('4k2r/8/8/8/8/8/8/R3K3 w - - 149 1');
    play(auto, 'a1a2');
    expect(auto.result?.reason, ChessEndReason.seventyFiveMoveRule);
    final pawn = fen('4k2r/8/8/8/8/8/P7/4K3 w - - 99 1');
    play(pawn, 'a2a3');
    expect(pawn.position.halfmoveClock, 0);
  });
  test('dead material is conservative and never draws bishop+knight', () {
    for (final rank in ['4K3', '3BK3', '3NK3']) {
      expect(
        fen('4k3/8/8/8/8/8/8/$rank w - - 0 1').result?.reason,
        ChessEndReason.deadPosition,
      );
    }
    for (final rank in ['2BNK3', '2NNK3', '2BBK3']) {
      expect(fen('4k3/8/8/8/8/8/8/$rank w - - 0 1').gameOver, false);
    }
  });
  test('agreement and resignation can be undone without losing state', () {
    final s = ChessSession();
    play(s, 'e2e4');
    final before = s.fen;
    s.agreeDraw();
    expect(s.result?.reason, ChessEndReason.drawAgreement);
    s.undo();
    expect(s.fen, before);
    expect(s.gameOver, false);
    s.resign(Side.black);
    expect(s.result?.winner, Side.white);
    s.undo();
    expect(s.fen, before);
    expect(s.moves.length, 1);
    s.undo();
    expect(s.fen, exportFen(ChessPosition.initial()));
  });
}
