import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../game_session.dart' show Cell, Side;
import '../../widgets/board_motion.dart';
import '../draughts_piece.dart';
import '../draughts_session.dart';

class DraughtsBoard extends StatelessWidget {
  const DraughtsBoard({
    super.key,
    required this.session,
    required this.onCell,
    this.selected,
    this.targets = const [],
    this.pendingPath = const [],
    this.flipped = false,
  });

  final DraughtsSession session;
  final ValueChanged<Cell> onCell;
  final Cell? selected;
  final List<Cell> targets;
  final List<Cell> pendingPath;
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    final size = session.rules.boardSize;
    final last = session.moves.lastOrNull;
    return AnimatedBoard<DraughtsPiece>(
      pieces: {
        for (var row = 0; row < size; row++)
          for (var col = 0; col < size; col++)
            Cell(row, col): ?session.pieceAt(Cell(row, col)),
      },
      history: session.moves,
      pieceKey: (piece) => (piece.side, piece.rank),
      configuration: (size, session.variant, flipped),
      move: last == null
          ? null
          : BoardMoveMotion.alongPath(last.path, last.captures),
      builder: (context, motion) => AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff38261c),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final square = constraints.maxWidth / size;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    GridView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: size * size,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: size,
                      ),
                      itemBuilder: (context, index) {
                        final visualRow = index ~/ size,
                            visualCol = index % size;
                        final row = flipped ? size - 1 - visualRow : visualRow;
                        final col = flipped ? size - 1 - visualCol : visualCol;
                        final cell = Cell(row, col);
                        final piece = session.pieceAt(cell);
                        return GestureDetector(
                          key: ValueKey('draughts-square-$row-$col'),
                          behavior: HitTestBehavior.opaque,
                          onTap: session.rules.isPlayable(cell)
                              ? () => onCell(cell)
                              : null,
                          child: AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 100),
                            decoration: BoxDecoration(
                              color: selected == cell
                                  ? const Color(0xffe6c85c)
                                  : pendingPath.contains(cell)
                                  ? const Color(0xffb9d69a)
                                  : (row + col).isEven
                                  ? const Color(0xffefdbb8)
                                  : const Color(0xff81583d),
                            ),
                            child: targets.contains(cell) && piece == null
                                ? Center(
                                    child: FractionallySizedBox(
                                      widthFactor: .3,
                                      heightFactor: .3,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: .75),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                    if (last != null)
                      IgnorePointer(
                        child: CustomPaint(
                          key: const ValueKey('draughts-last-move-trail'),
                          painter: _LastMoveTrailPainter(
                            path: last.path,
                            boardSize: size,
                            flipped: flipped,
                          ),
                        ),
                      ),
                    IgnorePointer(
                      child: ExcludeSemantics(
                        child: AnimatedBuilder(
                          animation: motion,
                          builder: (context, _) => Stack(
                            children: [
                              for (final frame in motion.frames)
                                Positioned(
                                  left:
                                      (flipped
                                          ? size - 1 - frame.position.dx
                                          : frame.position.dx) *
                                      square,
                                  top:
                                      (flipped
                                          ? size - 1 - frame.position.dy
                                          : frame.position.dy) *
                                      square,
                                  width: square,
                                  height: square,
                                  child: Opacity(
                                    opacity: frame.opacity,
                                    child: Transform.scale(
                                      scale: frame.scale,
                                      child: _piece(frame.piece, size),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _piece(DraughtsPiece piece, int size) => Padding(
    padding: const EdgeInsets.all(2),
    child: FractionallySizedBox(
      widthFactor: .88,
      heightFactor: .88,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: piece.side == Side.black
              ? const Color(0xff292725)
              : const Color(0xfff8f3e9),
          shape: BoxShape.circle,
          border: Border.all(
            color: piece.side == Side.black
                ? Colors.black
                : const Color(0xffc9bca4),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: piece.rank == DraughtsRank.king
            ? Icon(
                Icons.workspace_premium,
                size: size > 8 ? 14 : 19,
                color: piece.side == Side.black
                    ? const Color(0xffffd46b)
                    : const Color(0xff805214),
              )
            : null,
      ),
    ),
  );
}

/// A completed move is independent of the next selection and its capture
/// preview. Keep every landing, including a king's return to its source.
class _LastMoveTrailPainter extends CustomPainter {
  const _LastMoveTrailPainter({
    required this.path,
    required this.boardSize,
    required this.flipped,
  });

  final List<Cell> path;
  final int boardSize;
  final bool flipped;

  @override
  void paint(Canvas canvas, Size size) {
    final square = size.width / boardSize;
    Offset center(Cell cell) => Offset(
      ((flipped ? boardSize - 1 - cell.col : cell.col) + .5) * square,
      ((flipped ? boardSize - 1 - cell.row : cell.row) + .5) * square,
    );

    final points = path.map(center).toList(growable: false);
    final outline = Paint()
      ..color = const Color(0xff204b57)
      ..style = PaintingStyle.stroke
      ..strokeWidth = square * .105
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final trail = Paint()
      ..color = const Color(0xffb7e9f2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = square * .05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 1; i < points.length; i++) {
      final start = points[i - 1], end = points[i];
      canvas.drawLine(start, end, outline);
      canvas.drawLine(start, end, trail);
      final direction = (end - start) / (end - start).distance;
      final normal = Offset(-direction.dy, direction.dx);
      // Mid-segment arrows remain visible even when the destination is
      // occupied. They also distinguish the direction of a closed capture.
      final tip = Offset.lerp(start, end, .62)!;
      final base = tip - direction * square * .18;
      final arrow = Path()
        ..moveTo(
          (base + normal * square * .12).dx,
          (base + normal * square * .12).dy,
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          (base - normal * square * .12).dx,
          (base - normal * square * .12).dy,
        );
      canvas.drawPath(arrow, outline);
      canvas.drawPath(arrow, trail);
    }
    for (var i = 0; i < points.length - 1; i++) {
      final radius = square * (i == 0 ? .13 : .09);
      canvas.drawCircle(points[i], radius, outline);
      canvas.drawCircle(points[i], radius, trail);
    }
    // This halo stays outside the piece and marks the final landing even
    // when a multi-capture finishes on its original square.
    canvas.drawCircle(points.last, square * .455, outline);
    canvas.drawCircle(points.last, square * .455, trail);
  }

  @override
  bool shouldRepaint(covariant _LastMoveTrailPainter oldDelegate) =>
      boardSize != oldDelegate.boardSize ||
      flipped != oldDelegate.flipped ||
      !listEquals(path, oldDelegate.path);
}
