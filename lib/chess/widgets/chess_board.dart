import 'package:flutter/material.dart';
import '../chess.dart';

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
    final check = session.isInCheck(session.turn)
        ? ChessMoveGenerator.kingSquare(session.position, session.turn)
        : null;
    final last = session.moves.lastOrNull;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).height - 260).clamp(240, 600),
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.maxWidth / 8;
              return Column(
                children: List.generate(
                  8,
                  (visualRow) => Row(
                    children: List.generate(8, (visualCol) {
                      final cell = Cell(
                        flipped ? 7 - visualRow : visualRow,
                        flipped ? 7 - visualCol : visualCol,
                      );
                      final piece = session.position.pieceAt(cell);
                      final isTarget = targets.contains(cell);
                      var color = (cell.row + cell.col).isEven
                          ? const Color(0xffe7ddc9)
                          : const Color(0xff789284);
                      if (cell == last?.from || cell == last?.to) {
                        color = Color.lerp(color, Colors.amber, .42)!;
                      }
                      if (cell == check) color = const Color(0xffdc7373);
                      if (cell == selected) color = const Color(0xffd1bd63);
                      return Semantics(
                        label:
                            '${chessSquare(cell)} ${piece == null ? '空格' : '${piece.side.label}${piece.label}'}',
                        button: onCell != null,
                        child: GestureDetector(
                          key: ValueKey('square-${chessSquare(cell)}'),
                          onTap: onCell == null ? null : () => onCell!(cell),
                          child: Container(
                            width: size,
                            height: size,
                            color: color,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (piece != null)
                                  Text(
                                    piece.symbol,
                                    style: TextStyle(
                                      fontSize: size * .76,
                                      height: 1.1,
                                      color: piece.side == Side.white
                                          ? const Color(0xfffefdf6)
                                          : const Color(0xff17271f),
                                      shadows: const [
                                        Shadow(
                                          color: Color(0xff263b2d),
                                          blurRadius: 1.5,
                                          offset: Offset(.5, .5),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (isTarget)
                                  Container(
                                    width: piece == null
                                        ? size * .25
                                        : size * .88,
                                    height: piece == null
                                        ? size * .25
                                        : size * .88,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: piece == null
                                          ? Colors.black26
                                          : null,
                                      border: piece == null
                                          ? null
                                          : Border.all(
                                              color: Colors.black38,
                                              width: 3,
                                            ),
                                    ),
                                  ),
                                if (visualCol == 0)
                                  Positioned(
                                    top: 2,
                                    left: 3,
                                    child: Text(
                                      '${8 - cell.row}',
                                      style: TextStyle(
                                        fontSize: size * .18,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                if (visualRow == 7)
                                  Positioned(
                                    bottom: 1,
                                    right: 3,
                                    child: Text(
                                      chessSquare(cell)[0],
                                      style: TextStyle(
                                        fontSize: size * .18,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
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
            onPressed: () => Navigator.pop(context, move),
            child: Text(
              '${ChessPiece(side, move.promotion!).symbol}  ${ChessPiece(side, move.promotion!).label}',
              style: const TextStyle(fontSize: 24),
            ),
          ),
      ],
    ),
  );
}
