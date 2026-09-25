import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_sgf.dart';

void main() {
  test('undo preserves a single pass; pass again enters scoring', () {
    final g = GameSession(GameType.go);
    g.passGo();
    g.passGo();
    expect(g.turnLabel, '待确认计分');
    g.undo();
    expect(g.gameOver, false);
    g.passGo();
    expect(g.gameOver, true);
  });

  for (final n in [9, 13, 19]) {
    for (final h in [2, 3, 4, 5, 6, 7, 8, 9]) {
      test('$n board with $h handicap has correct center and count', () {
        final g = GameSession(
          GameType.go,
          goConfig: GoConfig(boardSize: n, handicap: h),
        );
        expect(g.board.expand((r) => r).whereType<GamePiece>().length, h);
        expect(g.pieceAt(Cell(n ~/ 2, n ~/ 2)) != null, h >= 5 && h.isOdd);
        expect(g.turn, Side.white);
        final imported = GoSgf.importGame(GoSgf.exportGame(g));
        expect(
          imported.board.map((r) => r.map((p) => p?.side).toList()).toList(),
          g.board.map((r) => r.map((p) => p?.side).toList()).toList(),
        );
        expect(imported.turn, Side.white);
      });
    }
  }

  test('ko rejects immediate recapture and undo restores ko state', () {
    final g = GameSession(
      GameType.go,
      goConfig: const GoConfig(rules: GoRuleSet.japanese),
    );
    g.setupGo({
      const Cell(0, 1): Side.black,
      const Cell(1, 0): Side.black,
      const Cell(2, 1): Side.black,
      const Cell(1, 1): Side.white,
      const Cell(0, 2): Side.white,
      const Cell(2, 2): Side.white,
      const Cell(1, 3): Side.white,
    }, Side.black);
    expect(g.placeGo(const Cell(1, 2)), true);
    expect(g.moves.last.captured, true);
    expect(g.placeGo(const Cell(1, 1)), false);
    g.placeGo(const Cell(8, 8));
    g.undo();
    expect(g.placeGo(const Cell(1, 1)), false);
    expect(g.blackCaptures, 1);
  });

  for (final rule in GoRuleSet.values) {
    test('dead group scores once under ${rule.name}', () {
      final g = GameSession(
        GameType.go,
        goConfig: GoConfig(boardSize: 9, rules: rule, komi: 0),
      );
      final stones = <Cell, Side>{};
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          stones[Cell(r, c)] = Side.black;
        }
      }
      stones[const Cell(4, 4)] = Side.white;
      stones[const Cell(4, 5)] = Side.white;
      g.setupGo(stones, Side.black);
      g.passGo();
      g.passGo();
      g.toggleDeadGoStone(const Cell(4, 4));
      expect(g.deadGoStones, {const Cell(4, 4), const Cell(4, 5)});
      expect(g.calculateGoScore().black, rule == GoRuleSet.chinese ? 81 : 4);
      g.confirmGoScore();
      expect(g.winner, Side.black);
      expect(g.toggleDeadGoStone(const Cell(4, 5)), false);
      final restored = GoSgf.importGame(GoSgf.exportGame(g));
      expect(restored.deadGoStones, g.deadGoStones);
      expect(restored.goScoreConfirmed, true);
      expect(restored.calculateGoScore().black, g.calculateGoScore().black);
      g.undo();
      expect(g.deadGoStones, isEmpty);
      expect(g.goScoreConfirmed, false);
      expect(g.gameOver, false);
    });
  }

  test('resume removes terminating passes and restores turn', () {
    final g = GameSession(GameType.go);
    g.placeGo(const Cell(3, 3));
    g.passGo();
    g.passGo();
    expect(g.resumeGo(), true);
    expect(g.moves.length, 1);
    expect(g.turn, Side.white);
    expect(g.placeGo(const Cell(4, 4)), true);
  });

  test('tree roundtrip retains sibling branches and multivalue properties', () {
    const input =
        r'(;GM[1]SZ[19]C[中文\]评论\\测试]AB[aa][bb];W[cc](;B[dd]C[一];W[ee])(;B[ff]TR[aa][bb]))';
    final output = GoSgf.exportRecord(GoSgf.parseRecord(input));
    expect(output, input);
    final g = GoSgf.importGame(input);
    expect(g.moves.length, 3);
    expect(g.pieceAt(const Cell(5, 5)), null);
    expect(g.pieceAt(const Cell(4, 4))?.side, Side.white);
    final roundtrip = GoSgf.parseRecord(GoSgf.exportGame(g));
    expect(roundtrip.root.comment, '中文]评论\\测试');
    expect(roundtrip.root.children.single.children.length, 2);
    g.placeGo(const Cell(6, 6));
    final resumed = GoSgf.importGame(GoSgf.exportGame(g));
    expect(resumed.moves.length, 4);
    expect(
      GoSgf.parseRecord(
        GoSgf.exportGame(g),
      ).root.children.single.children.length,
      2,
    );
    g.undo();
    g.undo();
    expect(GoSgf.importGame(GoSgf.exportGame(g)).moves.length, 2);
    g.reset();
    expect(GoSgf.parseRecord(GoSgf.exportGame(g)).root.comment, null);
    expect(GoSgf.importGame(GoSgf.exportGame(g)).moves, isEmpty);
  });

  test('SGF variations can be listed and replayed independently', () {
    const input = '(;SZ[9];B[aa];W[bb](;B[cc]C[主线])(;B[dd]C[变例];W[ee]))';
    final choices = GoSgf.variations(input);
    expect(choices, hasLength(2));
    expect(choices.map((v) => v.label), ['主线（3 手）', '变例 1（4 手）']);

    final main = GoSgf.importGame(input, variation: choices[0].choices);
    final variation = GoSgf.importGame(input, variation: choices[1].choices);
    expect(main.moves, hasLength(3));
    expect(variation.moves, hasLength(4));
    expect(main.pieceAt(const Cell(2, 2))?.side, Side.black);
    expect(variation.pieceAt(const Cell(3, 3))?.side, Side.black);
    expect(variation.pieceAt(const Cell(4, 4))?.side, Side.white);
    expect(
      GoSgf.exportGame(variation),
      contains('(;B[cc]C[主线])(;B[dd]C[变例];W[ee])'),
    );
    variation.placeGo(const Cell(5, 5));
    var edited = GoSgf.exportGame(variation);
    expect(edited, contains('(;B[cc]C[主线])(;B[dd]C[变例];W[ee];B[ff])'));
    variation.undo();
    variation.undo();
    variation.placeGo(const Cell(5, 5));
    edited = GoSgf.exportGame(variation);
    expect(edited, contains('(;B[cc]C[主线])(;B[dd]C[变例];W[ff])'));
  });

  test(
    'invalid SGF variation path fails instead of silently using main line',
    () {
      expect(
        () =>
            GoSgf.importGame('(;SZ[9];B[aa](;W[bb])(;W[cc]))', variation: [9]),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('territory surrounded by both colors is neutral for each ruleset', () {
    for (final rule in GoRuleSet.values) {
      final g = GameSession(
        GameType.go,
        goConfig: GoConfig(boardSize: 9, rules: rule, komi: 0),
      );
      final stones = <Cell, Side>{};
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          if (r == 4 && c == 4) continue;
          stones[Cell(r, c)] = (r == 3 && c == 4) ? Side.black : Side.white;
        }
      }
      g.setupGo(stones, Side.black);
      g.passGo();
      g.passGo();
      final score = g.calculateGoScore();
      expect(
        score.black + score.white,
        rule == GoRuleSet.chinese ? 80 : 0,
        reason: rule.name,
      );
    }
  });

  test('explicit handicap setup does not add automatic stones', () {
    final g = GoSgf.importGame('(;SZ[13]HA[2]AB[aa][bb]AW[cc]PL[W];W[dd])');
    expect(g.initialGoBoard.expand((r) => r).whereType<GamePiece>().length, 3);
    expect(g.moves.length, 1);
    expect(g.moves.first.side, Side.white);
    final saved = GoSgf.exportGame(g);
    expect(saved, contains('AB[aa][bb]'));
    expect(GoSgf.importGame(saved).moves.length, 1);
  });

  test('SGF same-color moves do not manufacture passes', () {
    final g = GoSgf.importGame('(;SZ[9];W[aa];W[bb])');
    expect(g.moves.length, 2);
    expect(g.moves.every((m) => m.side == Side.white && !m.pass), true);
    expect(GoSgf.exportGame(g), contains(';W[aa];W[bb]'));
  });

  test('compressed setup values and whitespace are accepted', () {
    final g = GoSgf.importGame(
      '(; GM [1] SZ [9] AB [aa:bb] [cc] AE[ab] PL[W]; C[comment] W[dd])',
    );
    expect(g.initialGoBoard.expand((r) => r).whereType<GamePiece>().length, 4);
    expect(g.moves.length, 1);
    expect(g.moves.first.side, Side.white);
  });

  for (final bad in [
    '',
    '(;SZ[9]',
    '(;SZ[9]C[unfinished)',
    '(;SZ[9]SZ[13])',
    '(;SZ[7])',
    '(;SZ[9];B[zz])',
    '(;SZ[9];B[aa];W[aa])',
    '(;SZ[9]KM[NaN])',
    '(;SZ[9]HA[15])',
    '(;SZ[9]PL[X])',
    '(;SZ[9];B[aa](;W[bb]);W[cc])',
    '(;SZ[9];B[aa]W[bb])',
    '(;SZ[9];B[aa];AB[cc])',
    '(;SZ[9])(;SZ[13])',
  ]) {
    test('invalid or unsupported SGF fails explicitly: $bad', () {
      expect(() => GoSgf.importGame(bad), throwsA(isA<FormatException>()));
    });
  }
}
