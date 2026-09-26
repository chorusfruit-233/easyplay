import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_record.dart';

void main() {
  test(
    'new moves append as preserved sibling variations and navigate by index',
    () {
      final record = GoSgfController(config: const GoConfig(boardSize: 9));
      final first = record.appendMove(
        const GameMove(to: Cell(2, 2), side: Side.black),
      );
      record.appendMove(const GameMove(to: Cell(3, 3), side: Side.white));
      expect(record.navigateParent(), true);
      record.appendMove(const GameMove(to: Cell(4, 4), side: Side.white));

      expect(record.root.children, hasLength(1));
      expect(first.children, hasLength(2));
      expect(first.isVariationPoint, true);
      expect(record.current.move?.to, const Cell(4, 4));
      expect(record.navigateParent(), true);
      expect(record.navigateChild(0), true);
      expect(record.current.move?.to, const Cell(3, 3));
      expect(record.navigateChild(1), false);
    },
  );

  test('SGF import keeps branches, setup, comments and arbitrary properties', () {
    const sgf =
        '(;GM[1]SZ[9]KM[6.5]AB[aa]C[root];B[bb]N[first](;W[cc]TR[bb])(;W[dd]C[alt]))';
    final record = GoSgfController.fromSgf(sgf, variation: [1]);

    expect(record.current.move?.to, const Cell(3, 3));
    expect(record.root.properties['C'], ['root']);
    expect(record.root.children.single.properties['N'], ['first']);
    expect(record.root.children.single.children, hasLength(2));
    expect(record.root.children.single.children.first.properties['TR'], ['bb']);
    expect(record.exportSgf(), contains('(;W[cc]TR[bb])(;W[dd]C[alt])'));

    final replay = record.sessionForCurrent();
    expect(replay.moves, hasLength(2));
    expect(replay.pieceAt(const Cell(0, 0))?.side, Side.black);
    expect(replay.pieceAt(const Cell(3, 3))?.side, Side.white);
  });

  test('pass, resignation, restart and current-path replay are recorded', () {
    final record = GoSgfController(config: const GoConfig(boardSize: 9));
    record.appendMove(const GameMove(to: Cell(2, 2), side: Side.black));
    record.appendPass(side: Side.white);
    record.appendResignation(Side.black);

    expect(record.current.resignedSide, Side.black);
    expect(record.exportSgf(), contains('W[]'));
    expect(record.exportSgf(), contains('RE[W+R]'));
    expect(record.sessionForCurrent().goResignedSide, Side.black);
    expect(record.navigateParent(), true);
    expect(record.current.move?.pass, true);
    record.restartCurrentBranch();
    expect(record.current, same(record.root));
    expect(record.sessionForCurrent().moves, isEmpty);
  });

  test('leaf lines expose selected branch indexes for serialization', () {
    final record = GoSgfController.fromSgf(
      '(;SZ[9];B[aa](;W[bb])(;W[cc];B[dd]))',
    );
    expect(record.leaves, hasLength(2));
    expect(record.variationChoices(record.leaves[0]), [0]);
    expect(record.variationChoices(record.leaves[1]), [1]);
  });

  test(
    'continuing after the first pass preserves the old double-pass ending',
    () {
      final record = GoSgfController(config: const GoConfig(boardSize: 9));
      record.appendPass(side: Side.black);
      final blackPass = record.current;
      record.appendPass(side: Side.white);
      final oldWhitePass = record.current;

      expect(record.navigateParent(), true);
      final continued = record.appendMove(
        const GameMove(to: Cell(2, 2), side: Side.white),
      );

      expect(blackPass.children, hasLength(2));
      expect(blackPass.children.first, same(oldWhitePass));
      expect(blackPass.children.first.move?.pass, true);
      expect(blackPass.children.last, same(continued));
      expect(record.sessionForCurrent().moves, hasLength(2));
      expect(
        record.sessionForCurrent().pieceAt(const Cell(2, 2))?.side,
        Side.white,
      );
      expect(record.sessionForCurrent().gameOver, false);
    },
  );

  test(
    'adding a move at a historical node keeps its existing continuation',
    () {
      final record = GoSgfController(config: const GoConfig(boardSize: 9));
      record.appendMove(const GameMove(to: Cell(0, 0), side: Side.black));
      final second = record.appendMove(
        const GameMove(to: Cell(1, 1), side: Side.white),
      );
      final oldVariation = record.appendMove(
        const GameMove(to: Cell(2, 2), side: Side.black),
      );

      expect(record.navigateParent(), true);
      final newVariation = record.appendMove(
        const GameMove(to: Cell(3, 3), side: Side.black),
      );

      expect(second.children, hasLength(2));
      expect(second.children, [oldVariation, newVariation]);
      expect(record.variationChoices(oldVariation), [0]);
      expect(record.variationChoices(newVariation), [1]);
      final replay = record.sessionForCurrent();
      expect(replay.moves, hasLength(3));
      expect(replay.pieceAt(const Cell(2, 2)), isNull);
      expect(replay.pieceAt(const Cell(3, 3))?.side, Side.black);
    },
  );

  test('SGF round trip keeps the selected path and every variation', () {
    final record = GoSgfController(config: const GoConfig(boardSize: 9));
    record.appendMove(const GameMove(to: Cell(0, 0), side: Side.black));
    record.appendMove(const GameMove(to: Cell(1, 1), side: Side.white));
    record.appendMove(const GameMove(to: Cell(2, 2), side: Side.black));
    expect(record.navigateParent(), true);
    final selectedBranch = record.appendMove(
      const GameMove(to: Cell(3, 3), side: Side.black),
    );
    record.appendMove(const GameMove(to: Cell(4, 4), side: Side.white));

    final selectedPath = record.variationChoices(record.current);
    final exported = record.exportSgf();
    final restored = GoSgfController.fromSgf(exported, variation: selectedPath);

    expect(selectedPath, [1]);
    expect(restored.variationChoices(restored.current), selectedPath);
    expect(
      restored.root.children.single.children.single.children,
      hasLength(2),
    );
    expect(restored.leaves, hasLength(2));
    expect(restored.current.parent?.move?.to, selectedBranch.move?.to);
    final replay = restored.sessionForCurrent();
    expect(replay.moves, hasLength(4));
    expect(replay.pieceAt(const Cell(2, 2)), isNull);
    expect(replay.pieceAt(const Cell(3, 3))?.side, Side.black);
    expect(replay.pieceAt(const Cell(4, 4))?.side, Side.white);
  });

  test(
    'root resignation result is projected to the selected terminal path',
    () {
      final record = GoSgfController.fromSgf('(;SZ[9]RE[B+R];B[aa])');

      final replay = record.sessionForCurrent();
      expect(replay.moves, hasLength(1));
      expect(replay.goResignedSide, Side.white);
      expect(replay.winner, Side.black);
      expect(record.exportSgf(), contains('RE[B+R]'));
    },
  );

  test('appended moves outside the configured board are rejected', () {
    final record = GoSgfController(config: const GoConfig(boardSize: 9));

    expect(
      () => record.appendMove(const GameMove(to: Cell(9, 0), side: Side.black)),
      throwsArgumentError,
    );
  });

  // The controller's root only records HA (the count), never AB (the
  // coordinates); handicap stones are reconstructed by GameSession.reset()
  // from that count. Nothing else pins that dependency down, so a change to
  // the constructor would silently drop them from every replay.
  test('handicap stones and white-to-move survive controller replay', () {
    const handicap3 = GoConfig(boardSize: 9, handicap: 3);
    const stones = [Cell(2, 6), Cell(6, 2), Cell(6, 6)];

    final record = GoSgfController(config: handicap3);
    expect(record.root.properties['HA'], ['3']);

    // A freshly built session, before any replay happens.
    final live = record.sessionForCurrent();
    expect(live.goConfig.handicap, 3);
    expect(live.initialGoTurn, Side.white, reason: '让子局应由白方先行');
    for (final cell in stones) {
      expect(live.pieceAt(cell)?.side, Side.black, reason: '缺少让子石 $cell');
    }

    // After moves are recorded the path is replayed through export/import.
    record.appendMove(const GameMove(to: Cell(4, 4), side: Side.white));
    record.appendMove(const GameMove(to: Cell(2, 2), side: Side.black));
    final replay = record.sessionForCurrent();

    expect(replay.goConfig.handicap, 3);
    expect(replay.moves, hasLength(2));
    // turn follows the last recorded move; the handicap's white-to-move is
    // carried by initialGoTurn.
    expect(replay.turn, Side.white);
    expect(replay.initialGoTurn, Side.white);
    expect(replay.pieceAt(const Cell(4, 4))?.side, Side.white);
    expect(replay.pieceAt(const Cell(2, 2))?.side, Side.black);

    // initialGoBoard is the position before the first recorded move, so the
    // handicap stones must be in it and the played stones must not be.
    for (final cell in stones) {
      expect(
        replay.initialGoBoard[cell.row][cell.col]?.side,
        Side.black,
        reason: '重放后让子石丢失 $cell',
      );
    }
    expect(replay.initialGoBoard[4][4], isNull);
    expect(replay.initialGoTurn, Side.white);
  });

  test('handicap survives a full SGF round trip through the controller', () {
    final record = GoSgfController(
      config: const GoConfig(boardSize: 9, handicap: 4),
    );
    record.appendMove(const GameMove(to: Cell(4, 4), side: Side.white));

    final restored = GoSgfController.fromSgf(record.exportSgf());
    final replay = restored.sessionForCurrent();

    expect(replay.goConfig.handicap, 4);
    expect(replay.initialGoTurn, Side.white);
    expect(replay.pieceAt(const Cell(2, 2))?.side, Side.black);
    expect(replay.pieceAt(const Cell(6, 6))?.side, Side.black);
  });

  test(
    'node annotations and deletion can preserve or remove continuations',
    () {
      final record = GoSgfController(config: const GoConfig(boardSize: 9));
      final first = record.appendMove(
        const GameMove(to: Cell(1, 1), side: Side.black),
      );
      record.setCurrentProperty('C', ['review this']);
      record.setCurrentProperty('TR', ['bb']);
      record.appendMove(const GameMove(to: Cell(2, 2), side: Side.white));
      expect(record.exportSgf(), contains('C[review this]TR[bb]'));

      expect(record.deleteCurrent(preserveChildren: false), isTrue);
      expect(record.current, same(first));
      expect(first.children, isEmpty);

      record.appendMove(const GameMove(to: Cell(2, 2), side: Side.white));
      record.navigateParent();
      expect(record.deleteCurrent(preserveChildren: true), isTrue);
      expect(record.root.children, hasLength(1));
      expect(record.root.children.single.move?.to, const Cell(2, 2));
    },
  );
}
