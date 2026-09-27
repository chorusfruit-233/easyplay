import 'package:flutter/material.dart';

import '../../game_session.dart' show Cell, Side;
import '../draughts_session.dart';

class DraughtsBoard extends StatelessWidget {
  const DraughtsBoard({
    super.key,
    required this.session,
    required this.onCell,
    this.selected,
    this.targets = const [],
    this.pendingPath = const [],
  });

  final DraughtsSession session;
  final ValueChanged<Cell> onCell;
  final Cell? selected;
  final List<Cell> targets;
  final List<Cell> pendingPath;

  @override
  Widget build(BuildContext context) {
    final size = session.rules.boardSize;
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff38261c),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: size * size,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: size,
            ),
            itemBuilder: (context, index) {
              final row = index ~/ size;
              final col = index % size;
              final cell = Cell(row, col);
              final piece = session.pieceAt(cell);
              final playable = session.rules.isPlayable(cell);
              final light = (row + col).isEven;
              final isSelected = selected == cell;
              final isTarget = targets.contains(cell);
              final isPath = pendingPath.contains(cell);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: playable ? () => onCell(cell) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xffe6c85c)
                        : isPath
                        ? const Color(0xffb9d69a)
                        : light
                        ? const Color(0xffefdbb8)
                        : const Color(0xff81583d),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isTarget && piece == null)
                        FractionallySizedBox(
                          widthFactor: .3,
                          heightFactor: .3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .75),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      if (piece != null)
                        Padding(
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
                              child: piece.rank.name == 'king'
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
                        ),
                    ],
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
