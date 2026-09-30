import 'package:flutter/material.dart';

import '../chess.dart';

/// Repo-owned vector artwork, independent of platform chess fonts/textures.
/// All six silhouettes use the same 100 × 100 coordinate system.
void paintChessPiece(Canvas canvas, Rect bounds, ChessPiece piece) {
  canvas.save();
  canvas.translate(bounds.left, bounds.top);
  canvas.scale(bounds.width / 100, bounds.height / 100);
  final white = piece.side == Side.white;
  final outline = Paint()
    ..color = white ? const Color(0xff34483f) : const Color(0xff101d19)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  final fill = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: white
          ? const [Color(0xfffffff5), Color(0xffdedbd0)]
          : const [Color(0xff4d6258), Color(0xff192923)],
    ).createShader(const Rect.fromLTWH(20, 10, 60, 80));
  final detail = Paint()
    ..color = white ? const Color(0xff617466) : const Color(0xffb5c4b3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void shape(Path path) {
    canvas.drawPath(path, fill);
    canvas.drawPath(path, outline);
  }

  void circle(double x, double y, double radius) {
    canvas.drawCircle(Offset(x, y), radius, fill);
    canvas.drawCircle(Offset(x, y), radius, outline);
  }

  void line(double x1, double y1, double x2, double y2) =>
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), detail);

  canvas.drawOval(
    const Rect.fromLTWH(19, 83, 62, 9),
    Paint()..color = const Color(0x260b1913),
  );
  switch (piece.type) {
    case ChessPieceType.pawn:
      shape(
        Path()
          ..moveTo(41, 41)
          ..lineTo(59, 41)
          ..cubicTo(56, 54, 57, 62, 69, 75)
          ..lineTo(31, 75)
          ..cubicTo(43, 62, 44, 54, 41, 41)
          ..close(),
      );
      circle(50, 29, 11);
      shape(
        Path()..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(36, 41, 28, 7),
            const Radius.circular(3),
          ),
        ),
      );
    case ChessPieceType.rook:
      shape(
        Path()
          ..moveTo(35, 39)
          ..lineTo(65, 39)
          ..lineTo(67, 68)
          ..lineTo(72, 75)
          ..lineTo(28, 75)
          ..lineTo(33, 68)
          ..close(),
      );
      shape(
        Path()
          ..moveTo(27, 18)
          ..lineTo(38, 18)
          ..lineTo(38, 28)
          ..lineTo(45, 28)
          ..lineTo(45, 18)
          ..lineTo(55, 18)
          ..lineTo(55, 28)
          ..lineTo(62, 28)
          ..lineTo(62, 18)
          ..lineTo(73, 18)
          ..lineTo(73, 37)
          ..lineTo(66, 43)
          ..lineTo(34, 43)
          ..lineTo(27, 37)
          ..close(),
      );
      line(35, 49, 65, 49);
      line(34, 67, 66, 67);
    case ChessPieceType.knight:
      shape(
        Path()
          ..moveTo(28, 75)
          ..cubicTo(28, 63, 33, 54, 46, 44)
          ..lineTo(34, 48)
          ..lineTo(25, 45)
          ..lineTo(21, 37)
          ..lineTo(37, 24)
          ..lineTo(40, 13)
          ..lineTo(49, 21)
          ..cubicTo(68, 20, 77, 36, 75, 54)
          ..lineTo(73, 75)
          ..close(),
      );
      canvas.drawPath(
        Path()
          ..moveTo(53, 29)
          ..cubicTo(67, 37, 66, 57, 57, 68),
        detail,
      );
      line(29, 39, 35, 40);
      circle(43, 32, 2.2);
      canvas.drawCircle(
        const Offset(43, 32),
        1.4,
        Paint()..color = detail.color,
      );
    case ChessPieceType.bishop:
      shape(
        Path()
          ..moveTo(40, 48)
          ..lineTo(60, 48)
          ..cubicTo(55, 61, 60, 67, 70, 75)
          ..lineTo(30, 75)
          ..cubicTo(40, 67, 45, 61, 40, 48)
          ..close(),
      );
      shape(
        Path()
          ..moveTo(50, 15)
          ..cubicTo(60, 23, 70, 33, 65, 42)
          ..cubicTo(61, 52, 39, 52, 35, 42)
          ..cubicTo(30, 33, 40, 23, 50, 15)
          ..close(),
      );
      circle(50, 14, 3.5);
      line(57, 26, 45, 39);
      line(38, 52, 62, 52);
      line(36, 69, 64, 69);
    case ChessPieceType.queen:
      shape(
        Path()
          ..moveTo(36, 47)
          ..lineTo(64, 47)
          ..lineTo(59, 60)
          ..lineTo(71, 75)
          ..lineTo(29, 75)
          ..lineTo(41, 60)
          ..close(),
      );
      shape(
        Path()
          ..moveTo(23, 28)
          ..lineTo(37, 39)
          ..lineTo(36, 21)
          ..lineTo(46, 36)
          ..lineTo(50, 16)
          ..lineTo(54, 36)
          ..lineTo(64, 21)
          ..lineTo(63, 39)
          ..lineTo(77, 28)
          ..lineTo(66, 50)
          ..lineTo(34, 50)
          ..close(),
      );
      for (final point in const [
        Offset(23, 26),
        Offset(36, 19),
        Offset(50, 14),
        Offset(64, 19),
        Offset(77, 26),
      ]) {
        circle(point.dx, point.dy, 3.2);
      }
      line(37, 55, 63, 55);
      line(35, 69, 65, 69);
    case ChessPieceType.king:
      shape(
        Path()
          ..moveTo(36, 44)
          ..lineTo(64, 44)
          ..lineTo(60, 60)
          ..lineTo(71, 75)
          ..lineTo(29, 75)
          ..lineTo(40, 60)
          ..close(),
      );
      shape(
        Path()
          ..moveTo(50, 33)
          ..cubicTo(29, 19, 22, 34, 35, 47)
          ..lineTo(65, 47)
          ..cubicTo(78, 34, 71, 19, 50, 33)
          ..close(),
      );
      shape(
        Path()
          ..moveTo(47, 10)
          ..lineTo(53, 10)
          ..lineTo(53, 17)
          ..lineTo(60, 17)
          ..lineTo(60, 23)
          ..lineTo(53, 23)
          ..lineTo(53, 32)
          ..lineTo(47, 32)
          ..lineTo(47, 23)
          ..lineTo(40, 23)
          ..lineTo(40, 17)
          ..lineTo(47, 17)
          ..close(),
      );
      line(37, 53, 63, 53);
      line(35, 69, 65, 69);
  }
  // A shared, stepped plinth keeps the silhouettes consistent at small sizes.
  shape(
    Path()
      ..moveTo(29, 74)
      ..lineTo(71, 74)
      ..lineTo(75, 80)
      ..lineTo(75, 87)
      ..lineTo(25, 87)
      ..lineTo(25, 80)
      ..close(),
  );
  line(29, 80, 71, 80);
  canvas.restore();
}

class ChessPieceIcon extends StatelessWidget {
  const ChessPieceIcon({super.key, required this.piece, this.size = 40});
  final ChessPiece piece;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _PiecePainter(piece)),
  );
}

class _PiecePainter extends CustomPainter {
  const _PiecePainter(this.piece);
  final ChessPiece piece;

  @override
  void paint(Canvas canvas, Size size) =>
      paintChessPiece(canvas, Offset.zero & size, piece);

  @override
  bool shouldRepaint(_PiecePainter oldDelegate) =>
      oldDelegate.piece.side != piece.side ||
      oldDelegate.piece.type != piece.type;
}
