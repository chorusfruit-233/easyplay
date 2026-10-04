import 'package:flutter/material.dart';
import '../xiangqi.dart';

void paintXiangqiPiece(
  Canvas canvas,
  Offset center,
  double radius,
  XiangqiPiece piece,
  ColorScheme colors,
) {
  final ink = piece.side == XiangqiSide.red ? colors.error : colors.onSurface;
  canvas.drawCircle(
    center,
    radius,
    Paint()..color = colors.surfaceContainerHigh,
  );
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * .065,
  );
  canvas.drawCircle(
    center,
    radius * .82,
    Paint()
      ..color = ink.withValues(alpha: .4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  final text = TextPainter(
    text: TextSpan(
      text: piece.label,
      style: TextStyle(
        color: ink,
        fontSize: radius * 1.35,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
}
