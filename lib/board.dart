import 'dart:math';

import 'package:flutter/material.dart';
import 'game_session.dart';
import 'go_placement.dart';

class Board extends StatefulWidget {
  final GameType type;
  final GameSession session;
  final Cell? selected;
  final List<Cell> targets;
  final ValueChanged<Cell> onCell;
  final GoPlacementMode placementMode;
  final ValueChanged<Cell>? onPreviewCell;
  final VoidCallback? onCancelPreview;
  const Board({
    super.key,
    required this.type,
    required this.session,
    required this.selected,
    required this.targets,
    required this.onCell,
    this.placementMode = GoPlacementMode.direct,
    this.onPreviewCell,
    this.onCancelPreview,
  });

  @override
  State<Board> createState() => _BoardState();
}

class _BoardState extends State<Board> {
  Cell? _preview;
  int? _activePointer;
  double _pointerStartY = 0;
  double _pointerDeltaY = 0;
  bool _pressReleaseActive = false;

  @override
  void didUpdateWidget(covariant Board oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placementMode != widget.placementMode) {
      _preview = null;
      _activePointer = null;
      _pressReleaseActive = false;
    }
  }

  Cell? _cellAt(Offset local, BoxConstraints constraints) {
    final n = widget.session.size;
    final cellSize = constraints.maxWidth / n;
    final col = widget.type == GameType.go
        ? ((local.dx - cellSize / 2) / cellSize).round()
        : (local.dx / cellSize).floor();
    final row = widget.type == GameType.go
        ? ((local.dy - cellSize / 2) / cellSize).round()
        : (local.dy / cellSize).floor();
    final cell = Cell(row, col);
    return widget.session.inside(cell) ? cell : null;
  }

  GoPlacementMode _resolvedMode(BoxConstraints constraints) {
    if (widget.placementMode != GoPlacementMode.automatic ||
        widget.type != GameType.go) {
      return widget.placementMode;
    }
    return constraints.maxWidth / widget.session.size >= 24
        ? GoPlacementMode.direct
        : GoPlacementMode.doubleTap;
  }

  void _previewCell(Cell? cell) {
    if (cell == null) return;
    _preview = cell;
    widget.onPreviewCell?.call(cell);
  }

  void _cancelPreview() {
    _preview = null;
    widget.onCancelPreview?.call();
  }

  void _commit(Cell? cell) {
    if (cell == null) return;
    _preview = null;
    widget.onCell(cell);
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final mode = _resolvedMode(constraints);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (mode == GoPlacementMode.pressRelease) {
              _activePointer = event.pointer;
              _pressReleaseActive = true;
              _previewCell(_cellAt(event.localPosition, constraints));
            } else if ((mode == GoPlacementMode.swipeConfirm ||
                    mode == GoPlacementMode.doubleTap) &&
                _preview != null) {
              _activePointer = event.pointer;
              _pointerStartY = event.localPosition.dy;
              _pointerDeltaY = 0;
            }
          },
          onPointerMove: (event) {
            if (_activePointer != event.pointer) return;
            if (_pressReleaseActive) {
              _previewCell(_cellAt(event.localPosition, constraints));
            } else {
              _pointerDeltaY = event.localPosition.dy - _pointerStartY;
            }
          },
          onPointerUp: (event) {
            if (_activePointer != event.pointer) return;
            if (_pressReleaseActive) {
              _commit(_cellAt(event.localPosition, constraints) ?? _preview);
            } else if (mode == GoPlacementMode.swipeConfirm) {
              if (_pointerDeltaY >= 24) {
                _commit(_preview);
              } else if (_pointerDeltaY <= -24) {
                _cancelPreview();
              }
            } else if (mode == GoPlacementMode.doubleTap &&
                _pointerDeltaY <= -24) {
              _cancelPreview();
            }
            _activePointer = null;
            _pressReleaseActive = false;
            _pointerDeltaY = 0;
          },
          onPointerCancel: (event) {
            if (_activePointer != event.pointer) return;
            if (_pressReleaseActive) _cancelPreview();
            _activePointer = null;
            _pressReleaseActive = false;
            _pointerDeltaY = 0;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final cell = _cellAt(details.localPosition, constraints);
              switch (mode) {
                case GoPlacementMode.direct:
                  _commit(cell);
                case GoPlacementMode.doubleTap:
                  if (_preview == cell) {
                    _commit(cell);
                  } else {
                    _previewCell(cell);
                  }
                case GoPlacementMode.swipeConfirm:
                case GoPlacementMode.automatic:
                  _previewCell(cell);
                case GoPlacementMode.pressRelease:
                  break;
              }
            },
            child: CustomPaint(
              painter: BoardPainter(
                type: widget.type,
                board: widget.session.board
                    .map((row) => List<GamePiece?>.of(row))
                    .toList(),
                selected: widget.selected,
                targets: List.of(widget.targets),
                deadStones: Set.of(widget.session.deadGoStones),
                lastMove:
                    widget.session.moves.isEmpty ||
                        widget.session.moves.last.pass
                    ? null
                    : widget.session.moves.last.to,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    ),
  );
}

class BoardPainter extends CustomPainter {
  final GameType type;
  final List<List<GamePiece?>> board;
  final Cell? selected;
  final List<Cell> targets;
  final Cell? lastMove;
  final Set<Cell> deadStones;
  BoardPainter({
    required this.type,
    required this.board,
    required this.selected,
    required this.targets,
    required this.lastMove,
    this.deadStones = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = board.length;
    final step = size.width / n;
    if (type == GameType.go) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
        Paint()..color = const Color(0xffdfad63),
      );
      final line = Paint()
        ..color = const Color(0xff573b25)
        ..strokeWidth = 1.1;
      for (var i = 0; i < n; i++) {
        final p = step * i + step / 2;
        canvas.drawLine(
          Offset(p, step / 2),
          Offset(p, size.height - step / 2),
          line,
        );
        canvas.drawLine(
          Offset(step / 2, p),
          Offset(size.width - step / 2, p),
          line,
        );
      }
      final star = Paint()..color = const Color(0xff573b25);
      final d = n == 9 ? 2 : 3;
      for (final r in [d, n ~/ 2, n - 1 - d]) {
        for (final c in [d, n ~/ 2, n - 1 - d]) {
          if (n == 9 && ((r == n ~/ 2) != (c == n ~/ 2))) continue;
          canvas.drawCircle(
            Offset(c * step + step / 2, r * step + step / 2),
            max(2, step * .045),
            star,
          );
        }
      }
    } else {
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          final dark = (r + c).isOdd;
          final color = type == GameType.chess
              ? (dark ? const Color(0xff779556) : const Color(0xffeeeed2))
              : (dark ? const Color(0xffa8623e) : const Color(0xffefd6aa));
          canvas.drawRect(
            Rect.fromLTWH(c * step, r * step, step, step),
            Paint()..color = color,
          );
        }
      }
    }
    if (selected != null) {
      canvas.drawRect(
        _cellRect(selected!, step),
        Paint()..color = const Color(0x6651a6ff),
      );
    }
    for (final target in targets) {
      final center = _center(target, step);
      if (board[target.row][target.col] == null) {
        canvas.drawCircle(
          center,
          step * .13,
          Paint()..color = const Color(0x99273339),
        );
      } else {
        canvas.drawCircle(
          center,
          step * .43,
          Paint()
            ..color = const Color(0x6651a6ff)
            ..style = PaintingStyle.stroke
            ..strokeWidth = step * .07,
        );
      }
    }
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final piece = board[r][c];
        if (piece == null) continue;
        final cell = Cell(r, c);
        if (type == GameType.go) {
          final center = _center(cell, step);
          canvas.drawCircle(
            center,
            step * .39,
            Paint()
              ..color = piece.side == Side.black
                  ? const Color(0xff171717)
                  : Colors.white,
          );
          canvas.drawCircle(
            center,
            step * .39,
            Paint()
              ..color = Colors.black38
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        } else if (type == GameType.checkers) {
          final center = _center(cell, step);
          canvas.drawCircle(
            center,
            step * .35,
            Paint()
              ..color = piece.side == Side.black
                  ? const Color(0xff27201d)
                  : const Color(0xfff4eee4),
          );
          canvas.drawCircle(
            center,
            step * .35,
            Paint()
              ..color = const Color(0x88000000)
              ..style = PaintingStyle.stroke
              ..strokeWidth = step * .045,
          );
          if (piece.kind == PieceKind.king) {
            _drawText(
              canvas,
              '♛',
              center,
              step * .42,
              piece.side == Side.black ? Colors.white : const Color(0xff51351c),
            );
          }
        } else {
          final glyph = switch (piece.kind) {
            PieceKind.king => '♚',
            PieceKind.queen => '♛',
            PieceKind.rook => '♜',
            PieceKind.bishop => '♝',
            PieceKind.knight => '♞',
            PieceKind.pawn => '♟',
            _ => '',
          };
          _drawText(
            canvas,
            glyph,
            _center(cell, step),
            step * .78,
            piece.side == Side.black
                ? const Color(0xff252525)
                : const Color(0xfffaf6e9),
            outline: piece.side == Side.white,
          );
        }
      }
    }
    for (final cell in deadStones) {
      final center = _center(cell, step);
      final offset = Offset(step * .25, step * .25);
      final paint = Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 2.5;
      canvas.drawLine(center - offset, center + offset, paint);
      canvas.drawLine(
        center + Offset(-offset.dx, offset.dy),
        center + Offset(offset.dx, -offset.dy),
        paint,
      );
    }
    if (lastMove != null && !deadStones.contains(lastMove)) {
      final center = _center(lastMove!, step);
      canvas.drawCircle(
        center,
        type == GameType.go ? step * .11 : step * .07,
        Paint()..color = const Color(0xffef5b35),
      );
    }
  }

  Offset _center(Cell cell, double step) => type == GameType.go
      ? Offset(cell.col * step + step / 2, cell.row * step + step / 2)
      : Offset((cell.col + .5) * step, (cell.row + .5) * step);
  Rect _cellRect(Cell cell, double step) =>
      Rect.fromLTWH(cell.col * step, cell.row * step, step, step);

  void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color, {
    bool outline = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: 'Noto Sans Symbols 2',
          color: color,
          shadows: outline
              ? const [Shadow(color: Colors.black, blurRadius: 1.5)]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
