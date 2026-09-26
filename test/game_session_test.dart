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

  group('Chess rules', () {
    test('starts with pieces and allows a pawn double-step', () {
      final game = GameSession(GameType.chess);
      expect(game.pieceAt(const Cell(0, 0))?.kind, PieceKind.rook);
      expect(game.pieceAt(const Cell(0, 4))?.kind, PieceKind.king);
      expect(game.legalMovesFrom(const Cell(1, 4)), [
        const Cell(2, 4),
        const Cell(3, 4),
      ]);
      expect(game.movePiece(const Cell(1, 4), const Cell(3, 4)), isTrue);
      expect(game.turn, Side.white);
    });

    test('does not allow a move that leaves its king in check', () {
      final game = GameSession(GameType.chess);
      game.board = List.generate(8, (_) => List<GamePiece?>.filled(8, null));
      game.board[7][4] = const GamePiece(Side.white, PieceKind.king);
      game.board[0][4] = const GamePiece(Side.black, PieceKind.rook);
      game.board[7][0] = const GamePiece(Side.white, PieceKind.rook);
      expect(game.legalMovesFrom(const Cell(7, 0)), isEmpty);
    });
  });

  test(
    'checkers starts with twelve pieces per side and restricts movement to dark squares',
    () {
      final game = GameSession(GameType.checkers);
      final blackCount = game.board
          .expand((row) => row)
          .where((piece) => piece?.side == Side.black)
          .length;
      final whiteCount = game.board
          .expand((row) => row)
          .where((piece) => piece?.side == Side.white)
          .length;
      expect(blackCount, 12);
      expect(whiteCount, 12);
      expect(game.legalMovesFrom(const Cell(2, 1)), [
        const Cell(3, 0),
        const Cell(3, 2),
      ]);
    },
  );
}
