import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../xiangqi.dart';
import 'xiangqi_piece_painter.dart';

/// Coordinates always remain red-at-bottom internally, including when flipped.
class XiangqiBoard extends StatelessWidget {
  const XiangqiBoard({
    super.key,
    required this.session,
    this.onCell,
    this.selected,
    this.targets = const [],
    this.flipped = false,
  });
  final XiangqiSession session;
  final ValueChanged<Cell>? onCell;
  final Cell? selected;
  final List<Cell> targets;
  final bool flipped;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableHeight = math.max(
        180.0,
        MediaQuery.sizeOf(context).height - 260,
      );
      final width = math.min(constraints.maxWidth, availableHeight * .9);
      return Center(
        child: SizedBox(
          width: width,
          height: width / .9,
          child: Semantics(
            label: '中国象棋棋盘，10 行 9 列',
            child: GestureDetector(
              onTapUp: onCell == null
                  ? null
                  : (details) {
                      final step = width / 9;
                      final col = (details.localPosition.dx / step - .5)
                          .round();
                      final row = (details.localPosition.dy / step - .5)
                          .round();
                      if (row < 0 || row > 9 || col < 0 || col > 8) return;
                      onCell!(
                        Cell(flipped ? 9 - row : row, flipped ? 8 - col : col),
                      );
                    },
              child: CustomPaint(
                painter: _BoardPainter(
                  session.position,
                  Theme.of(context).colorScheme,
                  selected,
                  targets,
                  flipped,
                  session.moves.isEmpty ? null : session.moves.last,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

// Web fallback fonts can arrive after the first TextPainter paint.
// Listening here also remeasures river labels when those fonts change.
class _BoardPainter extends CustomPainter {
  _BoardPainter(
    this.position,
    this.colors,
    this.selected,
    this.targets,
    this.flipped,
    this.last,
  ) : super(repaint: PaintingBinding.instance.systemFonts);
  final XiangqiPosition position;
  final ColorScheme colors;
  final Cell? selected;
  final List<Cell> targets;
  final bool flipped;
  final XiangqiMove? last;
  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / 9;
    Offset point(int row, int col) =>
        Offset((col + .5) * step, (row + .5) * step);
    Offset cell(Cell cell) => point(
      flipped ? 9 - cell.row : cell.row,
      flipped ? 8 - cell.col : cell.col,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = colors.surfaceContainer,
    );
    final grid = Paint()
      ..color = colors.outline
      ..strokeWidth = 1;
    for (var row = 0; row < 10; row++) {
      canvas.drawLine(point(row, 0), point(row, 8), grid);
    }
    for (var col = 0; col < 9; col++) {
      canvas.drawLine(point(0, col), point(4, col), grid);
      canvas.drawLine(point(5, col), point(9, col), grid);
    }
    for (final row in [0, 7]) {
      canvas.drawLine(point(row, 3), point(row + 2, 5), grid);
      canvas.drawLine(point(row, 5), point(row + 2, 3), grid);
    }
    for (final (label, col) in [('楚河', 2), ('汉界', 6)]) {
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: step * .45,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        point(4, col) + Offset(-text.width / 2, step / 2 - text.height / 2),
      );
    }
    for (final c in [
      if (last != null) last!.from,
      if (last != null) last!.to,
    ]) {
      canvas.drawCircle(
        cell(c),
        step * .46,
        Paint()..color = colors.primary.withValues(alpha: .2),
      );
    }
    for (var row = 0; row < 10; row++) {
      for (var col = 0; col < 9; col++) {
        final piece = position.board[row][col];
        final c = Cell(row, col);
        if (piece != null) {
          paintXiangqiPiece(canvas, cell(c), step * .41, piece, colors);
          if (piece.type == XiangqiPieceType.general &&
              XiangqiMoveGenerator.isInCheck(position, piece.side)) {
            canvas.drawCircle(
              cell(c),
              step * .46,
              Paint()
                ..color = colors.error
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3,
            );
          }
        }
        if (selected == c) {
          canvas.drawCircle(
            cell(c),
            step * .46,
            Paint()
              ..color = colors.primary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
        }
      }
    }
    for (final target in targets) {
      canvas.drawCircle(
        cell(target),
        step * .12,
        Paint()..color = colors.primary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
