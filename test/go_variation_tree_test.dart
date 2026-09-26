import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_record.dart';
import 'package:easyplay/go_variation_tree.dart';

/// Builds a record and returns the controller so tests can address nodes.
GoSgfController buildRecord() =>
    GoSgfController(config: const GoConfig(boardSize: 9));

void main() {
  test('a single line lays out flat on one lane', () {
    final record = buildRecord();
    for (var i = 0; i < 5; i++) {
      record.appendMove(
        GameMove(to: Cell(2 + i, 2), side: i.isEven ? Side.black : Side.white),
      );
    }

    final layout = GoVariationLayout.build(record.root);

    // root + five moves
    expect(layout.nodes, hasLength(6));
    expect(layout.edges, hasLength(5));
    expect(layout.nodes.map((n) => n.lane).toSet(), {0});
    expect(layout.nodes.map((n) => n.depth).toList(), [0, 1, 2, 3, 4, 5]);
    expect(layout.width, 6 * layout.columnWidth);
    expect(layout.height, layout.laneHeight);
  });

  test('a branch gets its own lane and never overlaps the main line', () {
    final record = buildRecord();
    record.appendMove(const GameMove(to: Cell(2, 2), side: Side.black));
    record.appendMove(const GameMove(to: Cell(3, 3), side: Side.white));
    // Step back and play a different white move: a sibling variation.
    record.navigateParent();
    record.appendMove(const GameMove(to: Cell(4, 4), side: Side.white));

    final layout = GoVariationLayout.build(record.root);

    // root, B, W, W
    expect(layout.nodes, hasLength(4));
    expect(layout.edges, hasLength(3));

    final byLane = <int, List<int>>{};
    for (final n in layout.nodes) {
      byLane.putIfAbsent(n.lane, () => []).add(n.depth);
    }
    // Two lanes: the main line, plus one for the sibling variation.
    expect(byLane.keys.toSet(), {0, 1});
    // The first child continues in the parent's lane.
    expect(byLane[0], [0, 1, 2]);
    // The sibling is one step deeper, alone in its own lane.
    expect(byLane[1], [2]);
    expect(layout.height, 2 * layout.laneHeight);

    // Every (depth, lane) pair is unique, so discs cannot overlap.
    final positions = layout.nodes.map((n) => '${n.depth}:${n.lane}').toSet();
    expect(positions, hasLength(layout.nodes.length));
  });

  test('three siblings from one node take three distinct lanes', () {
    final record = buildRecord();
    final first = record.appendMove(
      const GameMove(to: Cell(2, 2), side: Side.black),
    );
    // Appending to the same node each time produces siblings, not a chain.
    for (var i = 0; i < 3; i++) {
      record.navigateTo(first);
      record.appendMove(GameMove(to: Cell(3 + i, 3), side: Side.white));
    }

    final layout = GoVariationLayout.build(record.root);
    final positions = layout.nodes.map((n) => '${n.depth}:${n.lane}').toSet();

    expect(positions, hasLength(layout.nodes.length));
    // root + B + three sibling white moves
    expect(layout.nodes, hasLength(5));
    // The first sibling continues the main line; the other two take their own
    // lanes, so the tree is three lanes deep in total.
    expect(layout.nodes.map((n) => n.lane).toSet(), {0, 1, 2});
    expect(layout.height, 3 * layout.laneHeight);
  });

  test('move numbers count only move-bearing nodes', () {
    final record = buildRecord();
    final first = record.appendMove(
      const GameMove(to: Cell(2, 2), side: Side.black),
    );
    final pass = record.appendPass(side: Side.white);
    final resigned = record.appendResignation(Side.black);

    expect(GoVariationLayout.moveNumber(record.root), 0);
    expect(GoVariationLayout.moveNumber(first), 1);
    expect(GoVariationLayout.moveNumber(pass), 2);
    // Resignation carries no move of its own, so it repeats the last ordinal.
    expect(GoVariationLayout.moveNumber(resigned), 2);
  });

  test('nodeFor resolves the current node and reports absent ones', () {
    final record = buildRecord();
    final move = record.appendMove(
      const GameMove(to: Cell(2, 2), side: Side.black),
    );

    final layout = GoVariationLayout.build(record.root);
    expect(layout.nodeFor(move)?.depth, 1);
    expect(layout.nodeFor(record.root)?.depth, 0);

    // A node from a different record must not resolve.
    final other = buildRecord();
    expect(layout.nodeFor(other.root), isNull);
  });

  test('an empty record lays out without nodes or edges', () {
    final record = buildRecord();
    final layout = GoVariationLayout.build(record.root);

    expect(layout.nodes, hasLength(1)); // the root
    expect(layout.edges, isEmpty);
    expect(layout.width, layout.columnWidth);
    expect(layout.height, layout.laneHeight);
  });
}
