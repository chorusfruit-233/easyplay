import 'dart:math';

import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_record.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:easyplay/records/record_replay.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> withoutRevision(Map<String, Object?> state) =>
    Map.of(state)..remove('revision');

void main() {
  test('Go preserves setup, annotations, passes and every SGF variation', () {
    const sgf =
        '(;GM[1]FF[4]SZ[9]AB[aa]PL[W]C[setup]'
        ';W[dd]C[first]TR[dd](;B[cc];W[])(;B[ee]C[branch]))';
    final replay = GoRecordReplay(sgf);
    expect(replay.variations, ['主线', '变化 1']);
    expect(replay.length, 3);
    final initial = replay.frameAt(0).session as GameSession;
    expect(initial.board[0][0]?.side, Side.black);
    expect(initial.moves, isEmpty);
    final first = replay.frameAt(1);
    expect(first.comment, 'first');
    expect(first.annotations['TR'], ['dd']);
    expect((first.session as GameSession).moves, hasLength(1));
    final end = replay.frameAt(3).session as GameSession;
    expect(end.moves.last.pass, isTrue);
    expect(initial.moves, isEmpty);
    expect((first.session as GameSession).moves, hasLength(1));
    final branch = GoRecordReplay(sgf, variation: 1);
    expect(branch.length, 2);
    expect(branch.frameAt(2).comment, 'branch');
    final board = (branch.frameAt(2).session as GameSession).board;
    expect(board[4][4]?.side, Side.black);
    expect(board[2][2], isNull);
    expect(GoSgfController.fromSgf(sgf).leaves, hasLength(2));
  });

  test('Go resignation remains terminal and empty records remain playable', () {
    final replay = GoRecordReplay('(;GM[1]SZ[9]RE[B+R];B[dd];W[ee])');
    expect((replay.frameAt(1).session as GameSession).gameOver, isFalse);
    expect((replay.frameAt(2).session as GameSession).gameOver, isTrue);
    final empty = GoRecordReplay('(;GM[1]SZ[13])');
    expect(empty.length, 0);
    expect((empty.frameAt(0).session as GameSession).size, 13);
    expect(() => empty.frameAt(-1), throwsRangeError);
    expect(() => empty.frameAt(1), throwsRangeError);
  });

  test(
    'Soosyrv-8 replays decisions, candidates, selection and passes in order',
    () {
      final session = GomokuSession();
      final states = [withoutRevision(session.toJson())];
      void apply(GomokuAction action) {
        expect(session.applyAction(action), isTrue);
        states.add(withoutRevision(session.toJson()));
      }

      for (final cell in [
        const Cell(7, 7),
        const Cell(6, 7),
        const Cell(5, 7),
      ]) {
        apply(GomokuAction.place(cell));
      }
      apply(const GomokuAction.exchange(true));
      apply(const GomokuAction.place(Cell(9, 7)));
      apply(const GomokuAction.declare(2));
      apply(const GomokuAction.exchange(false));
      apply(const GomokuAction.place(Cell(6, 6)));
      apply(const GomokuAction.place(Cell(7, 5)));
      apply(GomokuAction.place(session.proposals.last));
      apply(const GomokuAction.pass());
      apply(const GomokuAction.pass());
      final record = GomokuRecord(
        id: 'competitive',
        createdAt: DateTime.utc(2026),
        session: session,
      );
      final original = record.toJson();
      final replay = GomokuRecordReplay(record);
      expect(replay.length, states.length - 1);
      for (var i = 0; i < states.length; i++) {
        final frame = replay.frameAt(i);
        expect(
          withoutRevision((frame.session as GomokuSession).toJson()),
          states[i],
        );
      }
      expect(replay.frameAt(4).description, contains('三手交换'));
      expect(replay.frameAt(6).description, contains('2 个候选点'));
      expect(replay.frameAt(7).description, contains('第二次交换'));
      expect(replay.frameAt(8).description, contains('提出黑5候选'));
      expect(replay.frameAt(10).description, contains('选择黑5'));
      expect((replay.frameAt(8).session as GomokuSession).moves, hasLength(4));
      expect((replay.frameAt(0).session as GomokuSession).moves, isEmpty);
      expect(record.toJson(), original);
    },
  );

  for (final variant in GomokuVariant.values) {
    test('${variant.name}: legacy and current records retain resignation', () {
      final session = GomokuSession(variant: variant)
        ..place(const Cell(7, 7))
        ..place(const Cell(6, 7))
        ..resign(Side.white);
      final replay = GomokuRecordReplay(
        GomokuRecord(
          id: variant.name,
          createdAt: DateTime.utc(2026),
          session: session,
        ),
      );
      expect(replay.length, 3);
      expect((replay.frameAt(2).session as GomokuSession).gameOver, isFalse);
      expect((replay.frameAt(3).session as GomokuSession).winner, Side.black);
      expect((replay.frameAt(1).session as GomokuSession).moves, hasLength(1));
    });
  }

  for (final variant in DraughtsVariant.values) {
    test(
      '${variant.name}: replay preserves paths, results and original state',
      () {
        final session = DraughtsSession(DraughtsRules.forVariant(variant));
        final random = Random(24);
        for (var i = 0; i < 40 && !session.gameOver; i++) {
          final moves = session.legalMoves();
          expect(
            session.applyMove(moves[random.nextInt(moves.length)]),
            isTrue,
          );
        }
        if (!session.gameOver) session.resign();
        final record = DraughtsRecord.fromSession(session);
        final original = record.toJson();
        final replay = DraughtsRecordReplay(record);
        expect((replay.frameAt(0).session as DraughtsSession).moves, isEmpty);
        final middle = replay.frameAt(5).session as DraughtsSession;
        expect(middle.moves, session.moves.take(5));
        final end = replay.frameAt(replay.length).session as DraughtsSession;
        expect(end.toJson(), session.toJson());
        expect(end.moves.map((m) => m.path), session.moves.map((m) => m.path));
        expect(
          (replay.frameAt(2).session as DraughtsSession).moves,
          hasLength(2),
        );
        expect(middle.moves, hasLength(5));
        expect(record.toJson(), original);
      },
    );
  }

  test('imported PDN replays and keeps an agreed draw as a final step', () {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.russian),
    );
    session.applyMove(session.legalMoves().first);
    session.agreeDraw();
    final record = DraughtsNotation.importPdn(
      DraughtsNotation.exportPdn(DraughtsRecord.fromSession(session)),
    );
    final replay = DraughtsRecordReplay(record);
    expect(replay.length, 2);
    expect((replay.frameAt(1).session as DraughtsSession).gameOver, isFalse);
    expect(
      (replay.frameAt(2).session as DraughtsSession).result?.isDraw,
      isTrue,
    );
    expect(replay.frameAt(2).description, '双方同意和棋');
  });
}
