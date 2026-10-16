import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_sgf.dart';

void main() {
  group('Go rules', () {
    test(
      'defaults to a 19-line Chinese rules board and rule-specific komi',
      () {
        expect(const GoConfig().boardSize, 19);
        expect(const GoConfig().rules, GoRuleSet.chinese);
        expect(const GoConfig().komi, 7.5);
        expect(const GoConfig(rules: GoRuleSet.japanese).komi, 6.5);
        expect(const GoConfig(rules: GoRuleSet.korean).komi, 6.5);
        expect(const GoConfig().copyWith(rules: GoRuleSet.japanese).komi, 6.5);
        expect(const GoConfig().copyWith(boardSize: 13).komi, 7.5);
      },
    );

    test(
      'KataGo final score overrides local estimates and confirms life/death',
      () {
        final game = GameSession(GameType.go);
        game.board[4][4] = const GamePiece(Side.white, PieceKind.stone);
        game.passGo();
        game.passGo();
        game.adjudicateGo(
          {const Cell(4, 4)},
          adjudicatedWinner: Side.black,
          margin: 12.5,
        );
        expect(game.goScoreConfirmed, isTrue);
        expect(game.deadGoStones, {const Cell(4, 4)});
        expect(game.calculateGoScore().winner, Side.black);
        expect(game.calculateGoScore().margin, 12.5);
      },
    );

    test('supports 13 and 19 line boards with handicap', () {
      final thirteen = GameSession(
        GameType.go,
        goConfig: const GoConfig(boardSize: 13),
      );
      expect(thirteen.size, 13);
      final nineteen = GameSession(
        GameType.go,
        goConfig: const GoConfig(boardSize: 19, handicap: 3),
      );
      expect(nineteen.size, 19);
      expect(nineteen.turn, Side.white);
      expect(
        nineteen.board.expand((row) => row).where((p) => p != null).length,
        3,
      );
      expect(nineteen.placeGo(const Cell(9, 9)), isTrue);
      expect(nineteen.undo(), isTrue);
      expect(nineteen.turn, Side.white);
      expect(
        nineteen.board.expand((row) => row).where((p) => p != null),
        hasLength(3),
      );
    });

    test('stopping twice ends the game and scoring applies komi', () {
      final game = GameSession(
        GameType.go,
        goConfig: const GoConfig(komi: 6.5),
      );
      expect(game.passGo(), isTrue);
      expect(game.gameOver, isFalse);
      expect(game.passGo(), isTrue);
      expect(game.gameOver, isTrue);
      expect(game.calculateGoScore().white, 6.5);
      expect(game.undo(), isTrue);
      expect(game.gameOver, isFalse);
      expect(game.moves, hasLength(1));
      expect(game.turn, Side.white);
      expect(game.passGo(), isTrue);
      expect(game.gameOver, isTrue);
    });

    test('exports and imports SGF moves', () {
      final game = GameSession(
        GameType.go,
        goConfig: const GoConfig(boardSize: 13, komi: 6.5),
      );
      game.placeGo(const Cell(3, 3));
      game.passGo();
      final sgf = GoSgf.exportGame(game);
      final restored = GoSgf.importGame(sgf);
      expect(restored.size, 13);
      expect(restored.goConfig.komi, 6.5);
      expect(restored.pieceAt(const Cell(3, 3))?.side, Side.black);
      expect(restored.moves.length, 2);
    });

    test('parses SGF comments and variations', () {
      final record = GoSgf.parseRecord(
        '(;GM[1]SZ[9]C[root];B[dd](;W[pp])(;W[qq]))',
      );
      expect(record.root.comment, 'root');
      expect(record.root.children, hasLength(1));
      expect(record.root.children.first.children, hasLength(2));
      expect(GoSgf.exportRecord(record), contains('C[root]'));
    });

    test('dead stone marks affect scoring without changing the board', () {
      final game = GameSession(GameType.go);
      game.passGo();
      game.passGo();
      game.board[0][0] = const GamePiece(Side.white, PieceKind.stone);
      expect(game.toggleDeadGoStone(const Cell(0, 0)), isTrue);
      expect(game.pieceAt(const Cell(0, 0))?.side, Side.white);
      expect(game.calculateGoScore().black, 0);
      expect(game.calculateGoScore().white, 7.5);
    });

    test('rejects occupied points and undo restores the turn', () {
      final game = GameSession(GameType.go);
      expect(game.placeGo(const Cell(4, 4)), isTrue);
      expect(game.isLegalGoMove(const Cell(4, 4)), isFalse);
      expect(game.placeGo(const Cell(4, 4)), isFalse);
      expect(game.turn, Side.white);
      expect(game.undo(), isTrue);
      expect(game.pieceAt(const Cell(4, 4)), isNull);
      expect(game.turn, Side.black);
    });

    test('live state changes are separate from the initial SGF generation', () {
      final game = GameSession(GameType.go);
      final recordRevision = game.revision;
      var stateRevision = game.stateRevision;

      void expectChanged() {
        expect(game.stateRevision, greaterThan(stateRevision));
        expect(game.revision, recordRevision);
        stateRevision = game.stateRevision;
      }

      expect(game.placeGo(const Cell(4, 4)), isTrue);
      expectChanged();
      expect(game.passGo(), isTrue);
      expectChanged();
      expect(game.undo(), isTrue);
      expectChanged();
      final lastMove = game.moves.last;
      expect(game.resignGo(), isTrue);
      expectChanged();
      expect(game.moves.last, same(lastMove));
      expect(game.undo(), isTrue);
      expectChanged();
      expect(game.moves.last, same(lastMove));

      game.reset();
      expect(game.stateRevision, greaterThan(stateRevision));
      expect(game.revision, greaterThan(recordRevision));
    });

    test(
      'scoring and resuming invalidate observers without replacing moves',
      () {
        final game = GameSession(GameType.go);
        game.setupGo({const Cell(4, 4): Side.white}, Side.black);
        game.passGo();
        game.passGo();
        final recordRevision = game.revision;
        final lastMove = game.moves.last;
        var stateRevision = game.stateRevision;

        expect(game.toggleDeadGoStone(const Cell(4, 4)), isTrue);
        expect(game.stateRevision, greaterThan(stateRevision));
        stateRevision = game.stateRevision;
        expect(game.confirmGoScore(), isTrue);
        expect(game.stateRevision, greaterThan(stateRevision));
        stateRevision = game.stateRevision;
        game.adjudicateGo({}, adjudicatedWinner: Side.white, margin: 3.5);
        expect(game.stateRevision, greaterThan(stateRevision));
        expect(game.moves.last, same(lastMove));
        stateRevision = game.stateRevision;
        expect(game.resumeGo(), isTrue);
        expect(game.stateRevision, greaterThan(stateRevision));
        expect(game.gameOver, isFalse);
        expect(game.revision, recordRevision);
      },
    );

    test('rejected operations leave both revisions unchanged', () {
      final game = GameSession(GameType.go);
      final recordRevision = game.revision;
      final stateRevision = game.stateRevision;
      expect(game.placeGo(const Cell(-1, 0)), isFalse);
      expect(game.undo(), isFalse);
      expect(game.toggleDeadGoStone(const Cell(4, 4)), isFalse);
      expect(game.confirmGoScore(), isFalse);
      expect(game.resumeGo(), isFalse);
      expect(
        () => game.setupGo({const Cell(-1, 0): Side.black}, Side.black),
        throwsArgumentError,
      );
      expect(
        () => game.adjudicateGo({}, adjudicatedWinner: Side.black, margin: 1),
        throwsStateError,
      );
      expect(game.stateRevision, stateRevision);
      expect(game.revision, recordRevision);

      game.placeGo(const Cell(4, 4));
      final moveRevision = game.stateRevision;
      expect(game.placeGo(const Cell(4, 4)), isFalse);
      expect(() => game.setupGo({}, Side.black), throwsStateError);
      expect(game.stateRevision, moveRevision);
      expect(game.revision, recordRevision);

      game.resignGo();
      final terminalRevision = game.stateRevision;
      expect(game.placeGo(const Cell(5, 5)), isFalse);
      expect(game.passGo(), isFalse);
      expect(game.resignGo(), isFalse);
      expect(game.toggleDeadGoStone(const Cell(4, 4)), isFalse);
      expect(game.stateRevision, terminalRevision);
      expect(game.revision, recordRevision);
    });

    test('setup and configuration advance the initial record generation', () {
      final game = GameSession(GameType.go);
      var recordRevision = game.revision;
      var stateRevision = game.stateRevision;
      game.setupGo({const Cell(2, 2): Side.black}, Side.white);
      expect(game.revision, greaterThan(recordRevision));
      expect(game.stateRevision, greaterThan(stateRevision));

      recordRevision = game.revision;
      stateRevision = game.stateRevision;
      game.setGoConfig(const GoConfig(boardSize: 13));
      expect(game.revision, greaterThan(recordRevision));
      expect(game.stateRevision, greaterThan(stateRevision));
    });

    test('rejects suicide and captures a surrounded group', () {
      final game = GameSession(GameType.go);
      for (final cell in [
        const Cell(3, 4),
        const Cell(5, 4),
        const Cell(4, 3),
        const Cell(4, 5),
      ]) {
        game.board[cell.row][cell.col] = const GamePiece(
          Side.white,
          PieceKind.stone,
        );
      }
      expect(game.isLegalGoMove(const Cell(4, 4)), isFalse);
      expect(game.placeGo(const Cell(4, 4)), isFalse);

      game.reset();
      game.board[4][4] = const GamePiece(Side.white, PieceKind.stone);
      game.board[3][4] = const GamePiece(Side.black, PieceKind.stone);
      game.board[5][4] = const GamePiece(Side.black, PieceKind.stone);
      game.board[4][3] = const GamePiece(Side.black, PieceKind.stone);
      expect(game.placeGo(const Cell(4, 5)), isTrue);
      expect(game.pieceAt(const Cell(4, 4)), isNull);
      expect(game.blackCaptures, 1);
    });

    test('rejects immediate ko recapture and restores ko after undo', () {
      final game = GameSession(
        GameType.go,
        goConfig: const GoConfig(rules: GoRuleSet.japanese),
      );
      game.setupGo({
        const Cell(0, 1): Side.black,
        const Cell(1, 0): Side.black,
        const Cell(2, 1): Side.black,
        const Cell(1, 1): Side.white,
        const Cell(0, 2): Side.white,
        const Cell(2, 2): Side.white,
        const Cell(1, 3): Side.white,
      }, Side.black);
      expect(game.isLegalGoMove(const Cell(1, 2)), isTrue);
      expect(game.placeGo(const Cell(1, 2)), isTrue);
      expect(game.isLegalGoMove(const Cell(1, 1)), isFalse);
      expect(game.placeGo(const Cell(1, 1)), isFalse);
      expect(game.placeGo(const Cell(8, 8)), isTrue);
      expect(game.undo(), isTrue);
      expect(game.isLegalGoMove(const Cell(1, 1)), isFalse);
      expect(game.blackCaptures, 1);
    });
  });

  test('legacy GameSession rejects Chess', () {
    expect(() => GameSession(GameType.chess), throwsUnsupportedError);
  });

  test(
    'legacy GameSession rejects Checkers after the rules were extracted',
    () {
      expect(() => GameSession(GameType.checkers), throwsUnsupportedError);
    },
  );
}
