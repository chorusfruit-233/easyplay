import 'dart:convert';

import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/chess/engine/chess_engine.dart';
import 'package:easyplay/records/board_record.dart';
import 'package:easyplay/records/board_record_notation.dart';
import 'package:easyplay/records/board_record_storage.dart';
import 'package:easyplay/records/record_replay.dart';
import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void chessMoves(ChessSession session, String moves) {
  for (final move in moves.split(' ')) {
    expect(session.applyMove(parseUciMove(move)), isTrue, reason: move);
  }
}

void xiangqiMoves(XiangqiSession session, String moves) {
  for (final move in moves.split(' ')) {
    expect(session.applyMove(parseXiangqiUciMove(move)), isTrue, reason: move);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('chess restores castling rights, en passant and underpromotion', () {
    final castle = ChessSession(
      position: parseFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'),
    );
    chessMoves(castle, 'e1g1 e8c8');
    final restored = ChessSession.fromJson(castle.toJson());
    expect(restored.fen, castle.fen);
    expect(restored.initialFen, castle.initialFen);
    castle.undo();
    restored.undo();
    expect(restored.fen, castle.fen);
    expect(restored.isLegalMove(parseUciMove('e8c8')), isTrue);

    final ep = ChessSession();
    chessMoves(ep, 'e2e4 a7a6 e4e5 d7d5 e5d6');
    final epRestored = ChessSession.fromJson(ep.toJson());
    expect(epRestored.fen, ep.fen);
    expect(epRestored.undo(), isTrue);
    expect(epRestored.isLegalMove(parseUciMove('e5d6')), isTrue);
    chessMoves(epRestored, 'e5d6');
    expect(epRestored.fen, ep.fen);

    final promotion = ChessSession(
      position: parseFen('4k3/P7/8/8/8/8/8/4K3 w - - 0 1'),
    );
    chessMoves(promotion, 'a7a8n');
    final promoted = ChessSession.fromJson(promotion.toJson());
    expect(promoted.result?.reason, ChessEndReason.deadPosition);
    expect(promoted.moves.single.promotion, ChessPieceType.knight);
    promoted.undo();
    expect(promoted.gameOver, isFalse);
    expect(promoted.fen, promotion.initialFen);
  });

  test('draw claims retain the declared move without applying it', () {
    final session = ChessSession();
    const cycle = 'g1f3 g8f6 f3g1 f6g8';
    chessMoves(session, '$cycle g1f3 g8f6 f3g1');
    final fen = session.fen;
    expect(session.claimableDraw(), isNull);
    expect(session.claimDraw(parseUciMove('f6g8')), isTrue);
    final restored = ChessSession.fromJson(session.toJson());
    expect(restored.fen, fen);
    expect(restored.moves, hasLength(7));
    expect(restored.result?.reason, ChessEndReason.threefoldRepetition);
    expect(restored.undo(), isTrue);
    expect(restored.gameOver, isFalse);
    chessMoves(restored, 'f6g8');
    expect(restored.repetitionCount, 3);
    expect(restored.claimDraw(), isTrue);
    expect(ChessSession.fromJson(restored.toJson()).result, restored.result);

    final fifty = ChessSession(
      position: parseFen('4k2r/8/8/8/8/8/8/R3K3 w - - 99 23'),
    );
    expect(fifty.claimDraw(parseUciMove('a1a2')), isTrue);
    final saved = ChessSession.fromJson(fifty.toJson());
    expect(saved.moves, isEmpty);
    expect(saved.fen, fifty.initialFen);
    expect(saved.result?.reason, ChessEndReason.fiftyMoveRule);
  });

  test('xiangqi restores long check and chase history before adjudication', () {
    for (final (fen, cycle) in [
      ('4k4/3R5/9/9/9/4P4/9/9/9/4K4 w - - 0 1', 'd8e8 e9d9 e8d8 d9e9'),
      ('4k4/9/9/9/9/3nP4/1R7/9/9/4K4 w - - 0 1', 'b3d3 d4b5 d3b3 b5d4'),
    ]) {
      final session = XiangqiSession(position: parseXiangqiFen(fen));
      xiangqiMoves(session, cycle);
      final restored = XiangqiSession.fromJson(session.toJson());
      xiangqiMoves(session, cycle);
      xiangqiMoves(restored, cycle);
      expect(restored.fen, session.fen);
      expect(restored.result, session.result);
      expect(restored.result?.reason, XiangqiEndReason.repetitionViolation);
      expect(restored.result?.winner, XiangqiSide.black);
      final terminal = XiangqiSession.fromJson(restored.toJson());
      expect(terminal.result, restored.result);
      expect(terminal.undo(), isTrue);
      expect(terminal.noCapturePlies, 7);
      expect(terminal.gameOver, isFalse);
      expect(terminal.applyMove(restored.moves.last), isTrue);
      expect(terminal.result, restored.result);
    }
  });

  test('xiangqi restores repetition draws and the no-capture clock', () {
    final repetition = XiangqiSession();
    const cycle = 'b0a2 b9a7 a2b0 a7b9';
    xiangqiMoves(repetition, '$cycle $cycle');
    expect(
      XiangqiSession.fromJson(repetition.toJson()).result?.reason,
      XiangqiEndReason.repetitionDraw,
    );
    final clock = XiangqiSession(
      position: parseXiangqiFen('r3k4/9/9/9/9/4P4/9/9/9/R3K4 w - - 119 1'),
    );
    xiangqiMoves(clock, 'a0a1');
    final restored = XiangqiSession.fromJson(clock.toJson());
    expect(restored.result?.reason, XiangqiEndReason.moveLimitDraw);
    restored.undo();
    expect(restored.noCapturePlies, 119);
    xiangqiMoves(restored, 'a0a9');
    expect(restored.noCapturePlies, 0);
    expect(restored.gameOver, isFalse);
  });

  test('both games restore resignation, agreement and undo', () {
    for (final draw in [false, true]) {
      final chess = ChessSession();
      chessMoves(chess, 'e2e4');
      draw ? chess.agreeDraw() : chess.resign(Side.black);
      final restored = ChessSession.fromJson(chess.toJson());
      expect(restored.result, chess.result);
      expect(restored.undo(), isTrue);
      expect(restored.gameOver, isFalse);
      expect(restored.moves, hasLength(1));

      final xiangqi = XiangqiSession();
      xiangqiMoves(xiangqi, 'h2e2');
      draw ? xiangqi.agreeDraw() : xiangqi.resign(XiangqiSide.black);
      final restoredXiangqi = XiangqiSession.fromJson(xiangqi.toJson());
      expect(restoredXiangqi.result, xiangqi.result);
      expect(restoredXiangqi.undo(), isTrue);
      expect(restoredXiangqi.gameOver, isFalse);
      expect(restoredXiangqi.moves, hasLength(1));
    }
  });

  test('records are independent snapshots and JSON imports get new ids', () {
    final session = ChessSession();
    chessMoves(session, 'e2e4 e7e5');
    final record = BoardGameRecord.fromChess(
      session,
      id: 'snapshot',
      createdAt: DateTime.utc(2026, 10, 28),
      kind: BoardRecordKind.ai,
      humanSide: Side.black,
      aiLevel: ChessAiLevel.hard,
    );
    final original = BoardRecordNotation.toJson(record);
    (record.toJson()['session'] as Map)['moves'] = [];
    chessMoves(session, 'g1f3');
    session.dispose();
    expect(record.restoreChess().moves, hasLength(2));
    expect(BoardRecordNotation.toJson(record), original);
    final imported = BoardRecordNotation.importJson(
      original,
      BoardRecordGame.chess,
    );
    expect(imported.id, isNot(record.id));
    expect(imported.createdAt, record.createdAt);
    expect(imported.kind, BoardRecordKind.ai);
    expect(imported.chessSide, Side.black);
    expect(imported.chessLevel, ChessAiLevel.hard);
    expect(imported.restoreChess().fen, record.restoreChess().fen);
    expect(
      () => BoardRecordNotation.importJson(original, BoardRecordGame.xiangqi),
      throwsFormatException,
    );
  });

  test('imports reject incompatible, illegal and forged terminal states', () {
    for (final game in BoardRecordGame.values) {
      final record = game == BoardRecordGame.chess
          ? BoardGameRecord.fromChess(ChessSession())
          : BoardGameRecord.fromXiangqi(XiangqiSession());
      void rejects(void Function(Map<String, dynamic>) edit) {
        final data =
            jsonDecode(BoardRecordNotation.toJson(record))
                as Map<String, dynamic>;
        edit(data);
        expect(
          () => BoardRecordNotation.importJson(jsonEncode(data), game),
          throwsFormatException,
        );
      }

      rejects((data) => data['version'] = 99);
      rejects((data) => data['session']['rulesVersion'] = 99);
      rejects((data) => data['session']['moves'] = ['a0a9']);
      rejects(
        (data) => data['session']['result'] = {
          'reason': 'checkmate',
          'winner': game == BoardRecordGame.chess ? 'white' : 'red',
        },
      );
      rejects(
        (data) => data['session']['result'] = {
          'reason': 'drawAgreement',
          'winner': 'black',
        },
      );
    }
    final mate = ChessSession();
    chessMoves(mate, 'f2f3 e7e5 g2g4 d8h4');
    final forged = mate.toJson();
    forged['moves'] = [...mate.moves.map(moveToUci), 'e1f2'];
    expect(() => ChessSession.fromJson(forged), throwsFormatException);
  });

  test(
    'PGN uses SAN, nonstandard FEN, correct black move numbers and results',
    () {
      final session = ChessSession(
        position: parseFen('4k2r/8/8/8/8/8/8/R3K3 b - - 0 42'),
      );
      chessMoves(session, 'h8h7 a1a2');
      final record = BoardGameRecord.fromChess(
        session,
        createdAt: DateTime.utc(2026, 10, 28),
      );
      final pgn = BoardRecordNotation.toPgn(record);
      expect(pgn, contains('[SetUp "1"]'));
      expect(pgn, contains('[FEN "${session.initialFen}"]'));
      expect(pgn, contains('[Date "2026.10.28"]'));
      expect(pgn, endsWith('42... Rh7 43. Ra2 *\n'));
      final mate = ChessSession();
      chessMoves(mate, 'f2f3 e7e5 g2g4 d8h4');
      expect(
        BoardRecordNotation.toPgn(BoardGameRecord.fromChess(mate)),
        endsWith('1. f3 e5 2. g4 Qh4# 0-1\n'),
      );
    },
  );

  test(
    'SAN disambiguates legal alternatives, castling, promotion and en passant',
    () {
      String san(String fen, String move) =>
          chessSan(ChessSession(position: parseFen(fen)), parseUciMove(move));
      expect(san('4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1', 'b1d2'), 'Nbd2');
      expect(san('4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1', 'f1d2'), 'Nfd2');
      expect(san('k3r3/8/8/8/8/8/2N1N3/4K3 w - - 0 1', 'c2d4'), 'Nd4');
      expect(san('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', 'e1g1'), 'O-O');
      expect(san('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', 'e1c1'), 'O-O-O');
      expect(san('4k3/P7/8/8/8/8/8/4K3 w - - 0 1', 'a7a8r'), 'a8=R+');
      final ep = ChessSession();
      chessMoves(ep, 'e2e4 a7a6 e4e5 d7d5');
      expect(chessSan(ep, parseUciMove('e5d6')), 'exd6');
      expect(ep.moves, hasLength(4));
    },
  );

  test('ICCS text retains coordinates, initial position and result', () {
    final session = XiangqiSession();
    xiangqiMoves(session, 'h2e2 h9g7');
    session.resign(XiangqiSide.red);
    final record = BoardGameRecord.fromXiangqi(session);
    final text = BoardRecordNotation.toIccs(record);
    expect(text, contains('1. H2-E2\n2. H9-G7'));
    expect(text, contains(session.initialFen));
    expect(text, contains('0-1'));
    final imported = BoardRecordNotation.importJson(
      BoardRecordNotation.toJson(record),
      BoardRecordGame.xiangqi,
    );
    expect(imported.restoreXiangqi().toJson(), session.toJson());
  });

  test('playback preserves initial positions, ending frames and snapshots', () {
    final chess = ChessSession(
      position: parseFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'),
    );
    chessMoves(chess, 'e1g1 e8c8');
    chess.resign(Side.white);
    final record = BoardGameRecord.fromChess(
      chess,
      kind: BoardRecordKind.online,
      humanSide: Side.black,
    );
    final original = BoardRecordNotation.toJson(record);
    final replay = ChessRecordReplay(record);
    expect(replay.flipped, isTrue);
    expect(replay.length, 3);
    expect((replay.frameAt(0).session as ChessSession).fen, chess.initialFen);
    expect((replay.frameAt(2).session as ChessSession).gameOver, isFalse);
    final end = replay.frameAt(3).session as ChessSession;
    expect(end.result, chess.result);
    end.undo();
    expect((replay.frameAt(3).session as ChessSession).result, chess.result);
    expect(replay.frameAt(1).description, contains('O-O'));
    expect(BoardRecordNotation.toJson(record), original);
    expect(() => replay.frameAt(4), throwsRangeError);
    final mate = ChessSession();
    chessMoves(mate, 'f2f3 e7e5 g2g4 d8h4');
    expect(ChessRecordReplay(BoardGameRecord.fromChess(mate)).length, 4);

    final xiangqi = XiangqiSession();
    xiangqiMoves(xiangqi, 'h2e2 h9g7');
    xiangqi.agreeDraw();
    final xReplay = XiangqiRecordReplay(BoardGameRecord.fromXiangqi(xiangqi));
    expect(xReplay.length, 3);
    expect((xReplay.frameAt(2).session as XiangqiSession).gameOver, isFalse);
    expect(
      (xReplay.frameAt(3).session as XiangqiSession).result,
      xiangqi.result,
    );
    expect(xReplay.frameAt(1).description, contains('H2 → E2'));
  });

  test(
    'storage serializes concurrent writes, updates ids and isolates games',
    () async {
      final chess = ChessSession();
      chessMoves(chess, 'e2e4');
      final first = BoardGameRecord.fromChess(
        chess,
        id: 'first',
        updatedAt: DateTime.utc(2026),
      );
      chessMoves(chess, 'e7e5');
      final updated = BoardGameRecord.fromChess(
        chess,
        id: 'first',
        updatedAt: DateTime.utc(2026, 2),
      );
      final second = BoardGameRecord.fromChess(
        chess,
        id: 'second',
        updatedAt: DateTime.utc(2026, 3),
      );
      final xiangqi = BoardGameRecord.fromXiangqi(
        XiangqiSession(),
        id: 'xiangqi',
      );
      final pending = [
        BoardRecordStorage.save(first),
        BoardRecordStorage.save(updated),
        BoardRecordStorage.save(second),
        BoardRecordStorage.save(xiangqi),
      ];
      final list = await BoardRecordStorage.list(BoardRecordGame.chess);
      await Future.wait(pending);
      expect(list.map((r) => r.id), ['second', 'first']);
      expect(list.last.moveCount, 2);
      await BoardRecordStorage.delete(BoardRecordGame.chess, 'second');
      expect(
        (await BoardRecordStorage.list(BoardRecordGame.chess)).single.id,
        'first',
      );
      expect(
        (await BoardRecordStorage.list(BoardRecordGame.xiangqi)).single.id,
        'xiangqi',
      );
    },
  );

  test(
    'storage retains more than one hundred records without eviction',
    () async {
      final session = ChessSession();
      chessMoves(session, 'e2e4');
      await Future.wait([
        for (var i = 0; i < 130; i++)
          BoardRecordStorage.save(
            BoardGameRecord.fromChess(session, id: 'game-$i'),
          ),
      ]);
      expect(
        await BoardRecordStorage.list(BoardRecordGame.chess),
        hasLength(130),
      );
    },
  );

  test(
    'corrupt storage cannot be silently overwritten and writes can retry',
    () async {
      final key = BoardRecordStorage.key(BoardRecordGame.chess);
      SharedPreferences.setMockInitialValues({key: '{broken'});
      final record = BoardGameRecord.fromChess(ChessSession());
      await expectLater(
        BoardRecordStorage.list(BoardRecordGame.chess),
        throwsFormatException,
      );
      await expectLater(BoardRecordStorage.save(record), throwsFormatException);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), '{broken');
      await prefs.remove(key);
      await BoardRecordStorage.save(record);
      expect(
        (await BoardRecordStorage.list(BoardRecordGame.chess)).single.id,
        record.id,
      );
    },
  );
}
