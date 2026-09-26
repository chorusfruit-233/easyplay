import 'package:flutter/material.dart';

import 'game_session.dart';
import 'go_record.dart';

/// One laid-out node of the variation tree.
///
/// [depth] is the number of moves from the root, [lane] the vertical slot it
/// occupies. Branches get their own lane so sibling variations are readable.
class GoVariationLayoutNode {
  final GoRecordNode node;
  final int depth;
  final int lane;
  const GoVariationLayoutNode(this.node, this.depth, this.lane);
}

/// Geometry and labels for the variation tree, kept free of Flutter so it can be
/// unit tested without a widget tree.
class GoVariationLayout {
  /// Horizontal distance between depths.
  final double columnWidth;

  /// Vertical distance between lanes.
  final double laneHeight;

  final List<GoVariationLayoutNode> nodes;
  final List<(GoVariationLayoutNode parent, GoVariationLayoutNode child)> edges;

  const GoVariationLayout._({
    required this.columnWidth,
    required this.laneHeight,
    required this.nodes,
    required this.edges,
  });

  double get width => nodes.isEmpty
      ? 0
      : (nodes.map((n) => n.depth).reduce((a, b) => a > b ? a : b) + 1) *
            columnWidth;

  double get height => nodes.isEmpty
      ? 0
      : (nodes.map((n) => n.lane).reduce((a, b) => a > b ? a : b) + 1) *
            laneHeight;

  /// Lays the tree out depth-first: the first child of every node continues in
  /// the parent's lane, later siblings descend into their own lane. This keeps a
  /// single-move game on one straight line, like a move list, and only spreads
  /// vertically where the record actually branches.
  factory GoVariationLayout.build(
    GoRecordNode root, {
    double columnWidth = 34,
    double laneHeight = 34,
  }) {
    final nodes = <GoVariationLayoutNode>[];
    final edges =
        <(GoVariationLayoutNode parent, GoVariationLayoutNode child)>[];
    var nextLane = 0;

    GoVariationLayoutNode visit(GoRecordNode node, int depth, int lane) {
      final laid = GoVariationLayoutNode(node, depth, lane);
      nodes.add(laid);
      for (var i = 0; i < node.children.length; i++) {
        final child = node.children[i];
        // The main line keeps the parent's lane; each further branch takes a
        // fresh lane below every lane used so far.
        final childLane = i == 0 ? lane : nextLane++;
        final laidChild = visit(child, depth + 1, childLane);
        edges.add((laid, laidChild));
      }
      return laid;
    }

    nextLane = 1; // lane 0 is reserved for the root and its main line
    visit(root, 0, 0);
    return GoVariationLayout._(
      columnWidth: columnWidth,
      laneHeight: laneHeight,
      nodes: List.unmodifiable(nodes),
      edges: List.unmodifiable(edges),
    );
  }

  GoVariationLayoutNode? nodeFor(GoRecordNode node) {
    for (final laid in nodes) {
      if (identical(laid.node, node)) return laid;
    }
    return null;
  }

  /// Move ordinal of [node], counting only move-bearing nodes on the path from
  /// the root. Resignation and bare-property nodes do not consume a number.
  static int moveNumber(GoRecordNode node) {
    var count = 0;
    for (GoRecordNode? cursor = node; cursor != null; cursor = cursor.parent) {
      if (cursor.move != null) count++;
    }
    return count;
  }
}

/// Renders an SGF record tree the way Go review tools do: the current node is a
/// blue triangle, moves are black/white discs numbered by move ordinal, and
/// straight lines join a node to its continuations.
class GoVariationTree extends StatelessWidget {
  final GoRecordNode root;
  final GoRecordNode current;
  final ValueChanged<GoRecordNode> onSelect;

  /// Diameter of a move disc.
  static const double nodeRadius = 13;

  const GoVariationTree({
    super.key,
    required this.root,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final layout = GoVariationLayout.build(root);
    final colors = Theme.of(context).colorScheme;
    final currentLaid = layout.nodeFor(current);

    return SizedBox(
      height: layout.height + nodeRadius * 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: layout.width + nodeRadius * 2,
          height: layout.height + nodeRadius * 2,
          child: Stack(
            children: [
              // Lines first so discs paint over them.
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgePainter(
                    layout: layout,
                    color: colors.outlineVariant,
                  ),
                ),
              ),
              for (final laid in layout.nodes)
                Positioned(
                  left: laid.depth * layout.columnWidth,
                  top: laid.lane * layout.laneHeight,
                  width: nodeRadius * 2,
                  height: nodeRadius * 2,
                  child: _VariationNodeDot(
                    laid: laid,
                    isCurrent: identical(laid, currentLaid),
                    colors: colors,
                    onTap: () => onSelect(laid.node),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariationNodeDot extends StatelessWidget {
  final GoVariationLayoutNode laid;
  final bool isCurrent;
  final ColorScheme colors;
  final VoidCallback onTap;

  const _VariationNodeDot({
    required this.laid,
    required this.isCurrent,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final node = laid.node;

    // The root carries no move: it marks the start of the record.
    if (node.isRoot) {
      return Tooltip(
        message: '棋谱起点',
        child: GestureDetector(
          onTap: onTap,
          child: CustomPaint(
            painter: _MarkerPainter(
              color: colors.outline,
              filled: false,
              radius: GoVariationTree.nodeRadius,
            ),
          ),
        ),
      );
    }

    // Resignation is recorded on a node with no move of its own.
    final resigned = node.resignedSide;
    final move = node.move;
    if (resigned == null && move == null) {
      // A node holding only comments or markup.
      return Tooltip(
        message: '第 ${GoVariationLayout.moveNumber(node)} 手后 · 注释节点',
        child: GestureDetector(
          onTap: onTap,
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isCurrent ? colors.primary : colors.outlineVariant,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
    }

    final isBlack = (move?.side ?? resigned!.opponent) == Side.black;
    final fill = isBlack ? const Color(0xff202124) : Colors.white;
    final label = resigned != null
        ? '认输'
        : move!.pass
        ? '停'
        : '${GoVariationLayout.moveNumber(node)}';
    final description = resigned != null
        ? '${resigned.label}认输'
        : move!.pass
        ? '${move.side!.label}停一手'
        : move.side!.label;

    return Tooltip(
      message: isCurrent
          ? '当前位置 · 第 ${GoVariationLayout.moveNumber(node)} 手 · $description'
          : '第 ${GoVariationLayout.moveNumber(node)} 手 · $description',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            // The current node keeps the stone's own colour and is marked with
            // a thicker primary-coloured ring rather than a separate marker.
            border: Border.all(
              color: isCurrent ? colors.primary : colors.outline,
              width: isCurrent ? 2.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: label.length > 2 ? 8 : 11,
              fontWeight: FontWeight.w600,
              color: isBlack ? Colors.white : const Color(0xff202124),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the blue triangle used for the current node, or a plain ring for the
/// record start.
class _MarkerPainter extends CustomPainter {
  final Color color;
  final bool filled;
  final double radius;

  const _MarkerPainter({
    required this.color,
    required this.filled,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius, center.dy + radius * 0.8)
      ..lineTo(center.dx - radius, center.dy + radius * 0.8)
      ..close();
    if (filled) {
      canvas
        ..drawPath(path, Paint()..color = color.withValues(alpha: .35))
        ..drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.color != color || old.filled != filled || old.radius != radius;
}

/// Draws the connector between every parent and child.
class _EdgePainter extends CustomPainter {
  final GoVariationLayout layout;
  final Color color;

  const _EdgePainter({required this.layout, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;

    for (final (parent, child) in layout.edges) {
      final from = Offset(
        parent.depth * layout.columnWidth + GoVariationTree.nodeRadius,
        parent.lane * layout.laneHeight + GoVariationTree.nodeRadius,
      );
      final to = Offset(
        child.depth * layout.columnWidth + GoVariationTree.nodeRadius,
        child.lane * layout.laneHeight + GoVariationTree.nodeRadius,
      );
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.layout != layout || old.color != color;
}
