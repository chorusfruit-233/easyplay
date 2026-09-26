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
  final Map<String, List<String>> annotations;
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
    this.annotations = const {},
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
    if (widget.selected == null && oldWidget.selected != null) {
      _preview = null;
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
                preview: _preview,
                previewSide: widget.session.turn,
                deadStones: Set.of(widget.session.deadGoStones),
                annotations: widget.annotations,
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
  final Cell? preview;
  final Side previewSide;
  final Set<Cell> deadStones;
  final Map<String, List<String>> annotations;
  BoardPainter({
    required this.type,
    required this.board,
    required this.selected,
    required this.targets,
    required this.lastMove,
    this.preview,
    this.previewSide = Side.black,
    this.deadStones = const {},
    this.annotations = const {},
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
    // Go confirmation uses the circular preview below. The generic square
    // selection highlight is only meaningful for chess/checkers and would
    // leave a translucent square behind the preview stone on a Go board.
    if (selected != null && type != GameType.go) {
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
    if (type == GameType.go &&
        preview != null &&
        insideBoard(preview!, n) &&
        board[preview!.row][preview!.col] == null) {
      final center = _center(preview!, step);
      const outerRing = Color(0xff5b9bd5);
      final radius = step * .39;

      // Render a light stone with two circular outlines. Keeping this entirely
      // circular avoids the old square alpha overlay and matches the preview
      // used by the reference client: blue focus ring plus a side-contrast
      // inner ring around the tentative stone.
      canvas.drawCircle(
        center,
        radius * .88,
        Paint()
          ..color = previewSide == Side.black
              ? const Color(0xb0505050)
              : const Color(0xd8fff1cf),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = outerRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(2, step * .045),
      );
      canvas.drawCircle(
        center,
        radius * .88,
        Paint()
          ..color = previewSide == Side.black
              ? const Color(0xfff5f1e6)
              : const Color(0xff4b3826)
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.5, step * .035),
      );
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
    if (type == GameType.go) {
      for (final (property, color, shape) in [
        ('TR', const Color(0xffb3261e), 'triangle'),
        ('SQ', const Color(0xffb3261e), 'square'),
        ('CR', const Color(0xffb3261e), 'circle'),
      ]) {
        for (final raw in annotations[property] ?? const <String>[]) {
          final cell = _sgfCell(raw, n);
          if (cell == null) continue;
          final center = _center(cell, step);
          final radius = step * .17;
          final paint = Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.5, step * .045);
          if (shape == 'circle') {
            canvas.drawCircle(center, radius, paint);
          } else if (shape == 'square') {
            canvas.drawRect(
              Rect.fromCenter(
                center: center,
                width: radius * 2,
                height: radius * 2,
              ),
              paint,
            );
          } else {
            final path = Path()
              ..moveTo(center.dx, center.dy - radius)
              ..lineTo(center.dx + radius, center.dy + radius)
              ..lineTo(center.dx - radius, center.dy + radius)
              ..close();
            canvas.drawPath(path, paint);
          }
        }
      }
      for (final raw in annotations['LB'] ?? const <String>[]) {
        final separator = raw.indexOf(':');
        if (separator != 2) continue;
        final cell = _sgfCell(raw.substring(0, separator), n);
        if (cell == null) continue;
        _drawText(
          canvas,
          raw.substring(separator + 1),
          _center(cell, step),
          step * .28,
          const Color(0xffb3261e),
          outline: true,
        );
      }
    }
  }

  Offset _center(Cell cell, double step) => type == GameType.go
      ? Offset(cell.col * step + step / 2, cell.row * step + step / 2)
      : Offset((cell.col + .5) * step, (cell.row + .5) * step);

  bool insideBoard(Cell cell, int n) =>
      cell.row >= 0 && cell.col >= 0 && cell.row < n && cell.col < n;
  Cell? _sgfCell(String raw, int n) {
    if (raw.length != 2) return null;
    final cell = Cell(raw.codeUnitAt(1) - 97, raw.codeUnitAt(0) - 97);
    return insideBoard(cell, n) ? cell : null;
  }

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
