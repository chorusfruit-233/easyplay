import 'dart:math';

import 'package:flutter/material.dart';
import 'game_session.dart';

class Board extends StatelessWidget {
  final GameType type;
  final GameSession session;
  final Cell? selected;
  final List<Cell> targets;
  final ValueChanged<Cell> onCell;
  const Board({
    super.key,
    required this.type,
    required this.session,
    required this.selected,
    required this.targets,
    required this.onCell,
  });

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final n = session.size;
          final cellSize = constraints.maxWidth / n;
          final local = details.localPosition;
          final col = type == GameType.go
              ? ((local.dx - cellSize / 2) / cellSize).round()
              : (local.dx / cellSize).floor();
          final row = type == GameType.go
              ? ((local.dy - cellSize / 2) / cellSize).round()
              : (local.dy / cellSize).floor();
          final cell = Cell(row, col);
          if (session.inside(cell)) onCell(cell);
        },
        child: CustomPaint(
          painter: BoardPainter(
            type: type,
            board: session.board
                .map((row) => List<GamePiece?>.of(row))
                .toList(),
            selected: selected,
            targets: List.of(targets),
            deadStones: Set.of(session.deadGoStones),
            lastMove: session.moves.isEmpty || session.moves.last.pass
                ? null
                : session.moves.last.to,
          ),
          child: const SizedBox.expand(),
        ),
      ),
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
      for (final r in [d, n ~/ 2, n - 1 - d])
        for (final c in [d, n ~/ 2, n - 1 - d]) {
          if (n == 9 && ((r == n ~/ 2) != (c == n ~/ 2))) continue;
          canvas.drawCircle(
            Offset(c * step + step / 2, r * step + step / 2),
            max(2, step * .045),
            star,
          );
        }
    } else {
      for (var r = 0; r < 8; r++)
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
    for (var r = 0; r < n; r++)
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
