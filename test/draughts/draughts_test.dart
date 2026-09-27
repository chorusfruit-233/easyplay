import 'package:flutter_test/flutter_test.dart';

import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/game_session.dart'
    show Cell, GameSession, GameType, Side;

void main() {
  group('variant setup', () {
    test(
      'all supported variants create playable positions and legal turns',
      () {
        for (final variant in DraughtsVariant.values) {
          final rules = DraughtsRules.forVariant(variant);
          final session = DraughtsSession(rules);
          final perSide =
              rules.startingRows *
              (rules.geometry == BoardGeometry.orthogonalAllSquares
                  ? rules.boardSize
                  : rules.boardSize ~/ 2);

          expect(
            session.position.count(Side.black),
            perSide,
            reason: variant.name,
          );
          expect(
            session.position.count(Side.white),
            perSide,
            reason: variant.name,
          );
          expect(session.turn, rules.firstMove, reason: variant.name);
          expect(session.legalMoves(), isNotEmpty, reason: variant.name);
        }
      },
    );

    test('Turkish men move forward and sideways on every square', () {
      final rules = DraughtsRules.forVariant(DraughtsVariant.turkish);
      final session = DraughtsSession(
        rules,
        position: position(8, {
          const Cell(2, 3): const DraughtsPiece(Side.black),
        }),
        turn: Side.black,
      );

      expect(rules.isPlayable(const Cell(2, 2)), isTrue);
      expect(
        session.legalMovesFrom(const Cell(2, 3)).map((move) => move.to).toSet(),
        {const Cell(3, 3), const Cell(2, 2), const Cell(2, 4)},
      );
    });

    test(
      'Italian capture tie-break prefers a king when capture count ties',
      () {
        final session = DraughtsSession(
          DraughtsRules.forVariant(DraughtsVariant.italian),
          position: position(8, {
            const Cell(2, 1): const DraughtsPiece(Side.black),
            const Cell(2, 5): const DraughtsPiece(
              Side.black,
              DraughtsRank.king,
            ),
            const Cell(3, 2): const DraughtsPiece(Side.white),
            const Cell(3, 6): const DraughtsPiece(Side.white),
          }),
          turn: Side.black,
        );

        expect(session.legalMoves(), hasLength(1));
        expect(session.legalMoves().single.from, const Cell(2, 5));
      },
    );
  });

  group('complete capture paths', () {
    test(
      'three jumps are one atomic move and undo restores the whole turn',
      () {
        final before = position(8, {
          const Cell(0, 1): const DraughtsPiece(Side.black),
          const Cell(1, 2): const DraughtsPiece(Side.white),
          const Cell(3, 4): const DraughtsPiece(Side.white),
          const Cell(5, 6): const DraughtsPiece(Side.white),
          const Cell(7, 0): const DraughtsPiece(Side.white),
        });
        final session = DraughtsSession(
          DraughtsRules.forVariant(DraughtsVariant.english),
          position: before,
          turn: Side.black,
        );

        final move = session.legalMoves().single;
        expect(move.path, [
          const Cell(0, 1),
          const Cell(2, 3),
          const Cell(4, 5),
          const Cell(6, 7),
        ]);
        expect(move.captures, [
          const Cell(1, 2),
          const Cell(3, 4),
          const Cell(5, 6),
        ]);
        expect(session.applyMove(move), isTrue);
        expect(session.moves, hasLength(1));
        expect(session.position.count(Side.white), 1);
        expect(session.turn, Side.white);
        expect(session.undo(), isTrue);
        expect(
          session.position.signature(session.turn),
          before.signature(Side.black),
        );
        expect(session.moves, isEmpty);
      },
    );

    test(
      'branching captures expose only complete paths and force the longest',
      () {
        final session = DraughtsSession(
          DraughtsRules.forVariant(DraughtsVariant.international),
          position: position(10, {
            const Cell(2, 1): const DraughtsPiece(Side.black),
            const Cell(3, 2): const DraughtsPiece(Side.white),
            const Cell(5, 4): const DraughtsPiece(Side.white),
            const Cell(2, 7): const DraughtsPiece(Side.black),
            const Cell(3, 8): const DraughtsPiece(Side.white),
          }),
          turn: Side.black,
        );

        final moves = session.legalMoves();
        expect(moves, hasLength(1));
        expect(moves.single.from, const Cell(2, 1));
        expect(moves.single.captures, hasLength(2));
        expect(moves.single.path.length, 3);
      },
    );

    test('flying king has every clear landing square after a victim', () {
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.international),
        position: position(10, {
          const Cell(4, 3): const DraughtsPiece(Side.white, DraughtsRank.king),
          const Cell(5, 4): const DraughtsPiece(Side.black),
        }),
        turn: Side.white,
      );

      expect(session.legalMoves().map((move) => move.to).toSet(), {
        const Cell(6, 5),
        const Cell(7, 6),
        const Cell(8, 7),
        const Cell(9, 8),
      });
    });

    test(
      'Russian man promotes during capture and continues as a flying king',
      () {
        final session = DraughtsSession(
          DraughtsRules.forVariant(DraughtsVariant.russian),
          position: position(8, {
            const Cell(5, 0): const DraughtsPiece(Side.black),
            const Cell(6, 1): const DraughtsPiece(Side.white),
            const Cell(5, 4): const DraughtsPiece(Side.white),
          }),
          turn: Side.black,
        );

        final move = session.legalMoves().firstWhere(
          (candidate) =>
              candidate.path[0] == const Cell(5, 0) &&
              candidate.path[1] == const Cell(7, 2),
        );
        expect(move.captures, hasLength(2));
        expect(session.applyMove(move), isTrue);
        expect(session.pieceAt(move.to)?.rank, DraughtsRank.king);
      },
    );

    test('promotion at end of an English capture stops the move', () {
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.english),
        position: position(8, {
          const Cell(5, 0): const DraughtsPiece(Side.black),
          const Cell(6, 1): const DraughtsPiece(Side.white),
        }),
        turn: Side.black,
      );

      expect(session.legalMoves().single.path, [
        const Cell(5, 0),
        const Cell(7, 2),
      ]);
      expect(session.applyMove(session.legalMoves().single), isTrue);
      expect(session.pieceAt(const Cell(7, 2))?.rank, DraughtsRank.king);
    });

    test('delayed removal clears every captured piece at turn end', () {
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.international),
        position: position(10, {
          const Cell(2, 1): const DraughtsPiece(Side.white, DraughtsRank.king),
          const Cell(3, 2): const DraughtsPiece(Side.black),
          const Cell(3, 4): const DraughtsPiece(Side.black),
        }),
        turn: Side.white,
      );
      final move = session.legalMoves().firstWhere(
        (candidate) => candidate.captures.length == 2,
      );

      expect(move.captures.toSet().length, 2);
      expect(session.applyMove(move), isTrue);
      expect(session.position.count(Side.black), 0);
      for (final captured in move.captures) {
        expect(session.pieceAt(captured), isNull);
      }
    });
  });

  test('session JSON restores exact position, turn, counters, and result', () {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
    );
    expect(session.applyMove(session.legalMoves().first), isTrue);
    final restored = DraughtsSession.fromJson(session.toJson());

    expect(
      restored.position.signature(restored.turn),
      session.position.signature(session.turn),
    );
    expect(restored.moves, session.moves);
    expect(restored.quietPlies, session.quietPlies);
    expect(() => GameSession(GameType.checkers), throwsUnsupportedError);
  });

  test('threefold repetition draws and undo restores the pending result', () {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
      position: position(8, {
        const Cell(2, 1): const DraughtsPiece(Side.black, DraughtsRank.king),
        const Cell(5, 6): const DraughtsPiece(Side.white, DraughtsRank.king),
      }),
      turn: Side.black,
    );
    final cycle = [
      (const Cell(2, 1), const Cell(3, 0)),
      (const Cell(5, 6), const Cell(4, 7)),
      (const Cell(3, 0), const Cell(2, 1)),
      (const Cell(4, 7), const Cell(5, 6)),
    ];

    for (var repetition = 0; repetition < 2; repetition++) {
      for (final (from, to) in cycle) {
        final move = session.legalMoves().firstWhere(
          (candidate) => candidate.from == from && candidate.to == to,
        );
        expect(session.applyMove(move), isTrue);
      }
    }
    expect(session.result?.reason, DraughtsEndReason.drawRule);
    expect(session.undo(), isTrue);
    expect(session.result, isNull);
  });

  test('no pieces, no moves, resignation, and agreement end the game', () {
    final rules = DraughtsRules.forVariant(DraughtsVariant.english);
    final noPieces = DraughtsSession(
      rules,
      position: position(8, {
        const Cell(2, 1): const DraughtsPiece(Side.white),
      }),
      turn: Side.black,
    );
    expect(noPieces.result?.reason, DraughtsEndReason.noPieces);
    expect(noPieces.result?.winner, Side.white);

    final noMoves = DraughtsSession(
      rules,
      position: position(8, {
        const Cell(7, 0): const DraughtsPiece(Side.black),
        const Cell(6, 1): const DraughtsPiece(Side.white),
      }),
      turn: Side.black,
    );
    expect(noMoves.result?.reason, DraughtsEndReason.noMoves);
    expect(noMoves.result?.winner, Side.white);

    final resignation = DraughtsSession(rules);
    expect(resignation.resign(Side.black), isTrue);
    expect(resignation.result?.winner, Side.white);

    final agreement = DraughtsSession(rules);
    expect(agreement.agreeDraw(), isTrue);
    expect(agreement.result?.reason, DraughtsEndReason.drawAgreement);
  });

  test('PDN export and import replay legal full paths', () {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
    );
    expect(session.applyMove(session.legalMoves().first), isTrue);
    final record = DraughtsRecord.fromSession(session, id: 'round-trip');
    final pdn = DraughtsNotation.exportPdn(record);
    final imported = DraughtsNotation.importPdn(pdn);

    expect(pdn, contains('[Variant "English"]'));
    expect(imported.variant, DraughtsVariant.english);
    expect(imported.moves, session.moves);
  });
}

DraughtsPosition position(int size, Map<Cell, DraughtsPiece> pieces) {
  var result = DraughtsPosition(size, List.filled(size * size, null));
  for (final entry in pieces.entries) {
    result = result.copyWithCell(entry.key, entry.value);
  }
  return result;
}
