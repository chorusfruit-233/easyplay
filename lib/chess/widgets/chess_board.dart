import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../chess.dart';
import 'chess_piece_painter.dart';

class ChessBoard extends StatelessWidget {
  const ChessBoard({
    super.key,
    required this.session,
    required this.onCell,
    this.selected,
    this.targets = const [],
    this.flipped = false,
  });
  final ChessSession session;
  final ValueChanged<Cell>? onCell;
  final Cell? selected;
  final List<Cell> targets;
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    // Capture immutable state, rather than retaining a mutable session in a
    // painter. Each position change invalidates the entire board, including
    // vacated squares, captures, castling and en passant.
    final position = session.position;
    final check = session.isInCheck(session.turn)
        ? ChessMoveGenerator.kingSquare(position, session.turn)
        : null;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).height - 260).clamp(240, 600),
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRect(
            child: CustomPaint(
              painter: _BoardPainter(
                position: position,
                last: session.moves.lastOrNull,
                check: check,
                selected: selected,
                targets: List.unmodifiable(targets),
                flipped: flipped,
              ),
              child: Column(
                children: List.generate(
                  8,
                  (visualRow) => Expanded(
                    child: Row(
                      children: List.generate(8, (visualCol) {
                        final cell = _cellAt(visualRow, visualCol, flipped);
                        final piece = position.pieceAt(cell);
                        return Expanded(
                          child: Semantics(
                            label:
                                '${chessSquare(cell)} ${piece == null ? '空格' : '${piece.side.label}${piece.label}'}',
                            button: onCell != null,
                            child: GestureDetector(
                              key: ValueKey('square-${chessSquare(cell)}'),
                              behavior: HitTestBehavior.opaque,
                              onTap: onCell == null
                                  ? null
                                  : () => onCell!(cell),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Cell _cellAt(int row, int col, bool flipped) =>
    Cell(flipped ? 7 - row : row, flipped ? 7 - col : col);

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.position,
    required this.last,
    required this.check,
    required this.selected,
    required this.targets,
    required this.flipped,
  });

  final ChessPosition position;
  final ChessMove? last;
  final Cell? check;
  final Cell? selected;
  final List<Cell> targets;
  final bool flipped;

  @override
  void paint(Canvas canvas, Size size) {
    final square = size.width / 8;
    final background = Paint();
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        final cell = _cellAt(row, col, flipped);
        final bounds = Rect.fromLTWH(
          col * square,
          row * square,
          square,
          square,
        );
        var color = (cell.row + cell.col).isEven
            ? const Color(0xffe7ddc9)
            : const Color(0xff789284);
        if (cell == last?.from || cell == last?.to) {
          color = Color.lerp(color, Colors.amber, .42)!;
        }
        if (cell == check) color = const Color(0xffdc7373);
        if (cell == selected) color = const Color(0xffd1bd63);
        canvas.drawRect(bounds, background..color = color);
        final piece = position.pieceAt(cell);
        if (piece != null) paintChessPiece(canvas, bounds, piece);
        if (targets.contains(cell)) {
          final marker = Paint()..color = const Color(0x55203327);
          if (piece == null) {
            canvas.drawCircle(bounds.center, square * .12, marker);
          } else {
            marker
              ..style = PaintingStyle.stroke
              ..strokeWidth = square * .045;
            canvas.drawCircle(bounds.center, square * .44, marker);
          }
        }
        void label(String text, Offset at) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                fontSize: square * .18,
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                color: const Color(0xff243c2f),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(canvas, at);
          painter.dispose();
        }

        if (col == 0) {
          label('${8 - cell.row}', bounds.topLeft + const Offset(3, 2));
        }
        if (row == 7) {
          label(
            chessSquare(cell)[0],
            bounds.bottomRight - Offset(square * .18, square * .22),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      position != oldDelegate.position ||
      last != oldDelegate.last ||
      check != oldDelegate.check ||
      selected != oldDelegate.selected ||
      flipped != oldDelegate.flipped ||
      !listEquals(targets, oldDelegate.targets);
}

Future<ChessMove?> chooseChessPromotion(
  BuildContext context,
  List<ChessMove> choices,
  Side side,
) {
  if (choices.length == 1) return Future.value(choices.single);
  return showDialog<ChessMove>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('选择升变棋子'),
      children: [
        for (final move in choices)
          SimpleDialogOption(
            key: ValueKey('promotion-${move.promotion!.name}'),
            onPressed: () => Navigator.pop(context, move),
            child: Row(
              children: [
                ChessPieceIcon(piece: ChessPiece(side, move.promotion!)),
                const SizedBox(width: 12),
                Text(
                  ChessPiece(side, move.promotion!).label,
                  style: const TextStyle(fontSize: 20),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
