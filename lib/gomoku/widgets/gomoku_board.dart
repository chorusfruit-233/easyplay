import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game_session.dart' show Cell, Side;
import '../../go_placement.dart';
import '../gomoku_session.dart';

/// Fits the whole board into the viewport, including narrow landscape screens.
class GomokuMatchLayout extends StatelessWidget {
  const GomokuMatchLayout({
    super.key,
    required this.header,
    required this.board,
    required this.footer,
  });

  final Widget header;
  final Widget board;
  final Widget footer;

  Widget _fittedBoard() => LayoutBuilder(
    builder: (_, constraints) => Center(
      child: SizedBox.square(
        dimension: math.min(constraints.maxWidth, constraints.maxHeight),
        child: board,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (_, constraints) {
        if (constraints.maxWidth >= 520 &&
            constraints.maxWidth > constraints.maxHeight * 1.2) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _fittedBoard()),
              const SizedBox(width: 16),
              SizedBox(
                width: (constraints.maxWidth * .32).clamp(180, 310),
                child: SingleChildScrollView(
                  child: Column(children: [header, footer]),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .3,
              ),
              child: SingleChildScrollView(child: header),
            ),
            Expanded(child: _fittedBoard()),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .25,
              ),
              child: SingleChildScrollView(child: footer),
            ),
          ],
        );
      },
    ),
  );
}

/// Intersection board shared by local and network matches.
class GomokuBoard extends StatefulWidget {
  const GomokuBoard({
    super.key,
    required this.session,
    required this.onCell,
    this.enabled = true,
    this.placementMode = GoPlacementMode.direct,
    this.onPreviewCell,
    this.onCancelPreview,
  });

  final GomokuSession session;
  final ValueChanged<Cell> onCell;
  final bool enabled;
  final GoPlacementMode placementMode;
  final ValueChanged<Cell>? onPreviewCell;
  final VoidCallback? onCancelPreview;

  @override
  State<GomokuBoard> createState() => _GomokuBoardState();
}

class _GomokuBoardState extends State<GomokuBoard> {
  Cell? _preview;
  int? _pointer;
  Offset? _start;
  late int _revision = widget.session.revision;

  @override
  void didUpdateWidget(covariant GomokuBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_revision != widget.session.revision ||
        oldWidget.session != widget.session ||
        oldWidget.placementMode != widget.placementMode ||
        !widget.enabled) {
      _preview = null;
      _pointer = null;
      _start = null;
      _revision = widget.session.revision;
    }
  }

  Cell? _cellAt(Offset point, double dimension) {
    if (point.dx < 0 ||
        point.dy < 0 ||
        point.dx >= dimension ||
        point.dy >= dimension) {
      return null;
    }
    final step = dimension / widget.session.size;
    final cell = Cell(
      ((point.dy - step / 2) / step).round(),
      ((point.dx - step / 2) / step).round(),
    );
    return widget.session.inside(cell) && widget.session.pieceAt(cell) == null
        ? cell
        : null;
  }

  void _select(Cell? cell) {
    if (!mounted) return;
    setState(() => _preview = cell);
    if (cell == null) {
      widget.onCancelPreview?.call();
    } else {
      widget.onPreviewCell?.call(cell);
    }
  }

  void _commit(Cell? cell) {
    _select(null);
    if (cell != null && widget.enabled && !widget.session.gameOver) {
      widget.onCell(cell);
    }
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final dimension = math.min(constraints.maxWidth, constraints.maxHeight);
        final mode = widget.placementMode == GoPlacementMode.automatic
            ? (dimension / widget.session.size >= 24
                  ? GoPlacementMode.direct
                  : GoPlacementMode.doubleTap)
            : widget.placementMode;
        return Semantics(
          label: '${widget.session.variant.label}棋盘，15 行 15 列',
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if (!widget.enabled ||
                  widget.session.gameOver ||
                  _pointer != null) {
                return;
              }
              _pointer = event.pointer;
              _start = event.localPosition;
              if (mode == GoPlacementMode.pressRelease) {
                _select(_cellAt(event.localPosition, dimension));
              }
            },
            onPointerMove: (event) {
              if (_pointer != event.pointer) return;
              if (mode == GoPlacementMode.pressRelease) {
                _select(_cellAt(event.localPosition, dimension));
              }
            },
            onPointerCancel: (event) {
              if (_pointer != event.pointer) return;
              _pointer = null;
              _start = null;
              _select(null);
            },
            onPointerUp: (event) {
              if (_pointer != event.pointer) return;
              final delta = event.localPosition - _start!;
              _pointer = null;
              _start = null;
              final cell = _cellAt(event.localPosition, dimension);
              if (mode == GoPlacementMode.pressRelease) {
                _commit(cell);
                return;
              }
              if (_preview != null && delta.dy <= -24) {
                _select(null);
                return;
              }
              if (mode == GoPlacementMode.swipeConfirm &&
                  _preview != null &&
                  delta.dy >= 24) {
                _commit(_preview);
                return;
              }
              if (delta.distance > 12 || cell == null) return;
              switch (mode) {
                case GoPlacementMode.direct:
                  _commit(cell);
                case GoPlacementMode.doubleTap:
                  if (_preview == cell) {
                    _commit(cell);
                  } else {
                    _select(cell);
                  }
                case GoPlacementMode.swipeConfirm:
                  _select(cell);
                case GoPlacementMode.pressRelease:
                case GoPlacementMode.automatic:
                  break;
              }
            },
            child: CustomPaint(
              painter: _GomokuPainter(
                pieces: [
                  for (var row = 0; row < widget.session.size; row++)
                    [
                      for (var col = 0; col < widget.session.size; col++)
                        widget.session.pieceAt(Cell(row, col)),
                    ],
                ],
                last: widget.session.moves.lastOrNull?.cell,
                winningLine: List.of(widget.session.winningLine),
                preview: _preview,
                previewSide: widget.session.turn,
                accent: Theme.of(context).colorScheme.primary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    ),
  );
}

class _GomokuPainter extends CustomPainter {
  _GomokuPainter({
    required this.pieces,
    required this.last,
    required this.winningLine,
    required this.preview,
    required this.previewSide,
    required this.accent,
  });

  final List<List<Side?>> pieces;
  final Cell? last;
  final List<Cell> winningLine;
  final Cell? preview;
  final Side previewSide;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / pieces.length;
    Offset point(Cell cell) =>
        Offset((cell.col + .5) * step, (cell.row + .5) * step);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      Paint()..color = const Color(0xffdfb979),
    );
    final grid = Paint()
      ..color = const Color(0xff6b4e2e)
      ..strokeWidth = math.max(.7, step * .025);
    for (var index = 0; index < pieces.length; index++) {
      final start = (index + .5) * step;
      canvas.drawLine(
        Offset(step / 2, start),
        Offset(size.width - step / 2, start),
        grid,
      );
      canvas.drawLine(
        Offset(start, step / 2),
        Offset(start, size.height - step / 2),
        grid,
      );
    }
    for (final row in [3, 7, 11]) {
      for (final col in [3, 7, 11]) {
        if ((row == 7) != (col == 7)) continue;
        canvas.drawCircle(point(Cell(row, col)), step * .08, grid);
      }
    }
    void stone(Cell cell, Side side, {bool ghost = false}) {
      final center = point(cell);
      final radius = step * .43;
      final fill = Paint()
        ..color =
            (side == Side.black
                    ? const Color(0xff202020)
                    : const Color(0xfff5f5f5))
                .withValues(alpha: ghost ? .55 : 1);
      if (!ghost) {
        canvas.drawCircle(
          center + Offset(step * .03, step * .05),
          radius,
          Paint()..color = Colors.black.withValues(alpha: .18),
        );
      }
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0xff474747).withValues(alpha: ghost ? .5 : 1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.6, step * .025),
      );
    }

    for (var row = 0; row < pieces.length; row++) {
      for (var col = 0; col < pieces.length; col++) {
        final side = pieces[row][col];
        if (side != null) stone(Cell(row, col), side);
      }
    }
    if (last != null) {
      canvas.drawCircle(
        point(last!),
        step * .12,
        Paint()
          ..color = pieces[last!.row][last!.col] == Side.black
              ? Colors.white
              : Colors.black,
      );
    }
    if (winningLine.length >= 5) {
      canvas.drawLine(
        point(winningLine.first),
        point(winningLine.last),
        Paint()
          ..color = accent
          ..strokeWidth = step * .13
          ..strokeCap = StrokeCap.round,
      );
    }
    if (preview != null) stone(preview!, previewSide, ghost: true);
  }

  @override
  bool shouldRepaint(covariant _GomokuPainter oldDelegate) => true;
}
