import 'package:flutter/material.dart';
import '../game_session.dart';

/// Small theme-aware illustrations, independent of game state and fonts.
class GameArtwork extends StatelessWidget {
  const GameArtwork({super.key, required this.type, this.size = 48});
  final GameType type;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GameArtworkPainter(type, Theme.of(context).colorScheme),
      ),
    ),
  );
}

class _GameArtworkPainter extends CustomPainter {
  _GameArtworkPainter(this.type, this.colors);
  final GameType type;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final fill = Paint()..color = colors.primaryContainer;
    final line = Paint()
      ..color = colors.primary.withValues(alpha: .5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final stone = Paint()..color = colors.primary;
    if (type == GameType.doudizhu) {
      for (var i = 0; i < 3; i++) {
        canvas.save();
        canvas.translate(24, 25);
        canvas.rotate((i - 1) * .22);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(-13 + i * 3, -18, 22, 32),
            const Radius.circular(4),
          ),
          Paint()
            ..color = i == 1
                ? colors.tertiaryContainer
                : colors.primaryContainer,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(-13 + i * 3, -18, 22, 32),
            const Radius.circular(4),
          ),
          line,
        );
        canvas.restore();
      }
      canvas.drawPath(
        Path()
          ..moveTo(26, 17)
          ..lineTo(32, 25)
          ..lineTo(26, 33)
          ..lineTo(20, 25)
          ..close(),
        Paint()..color = colors.tertiary,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 2, 44, 44),
          const Radius.circular(8),
        ),
        fill,
      );
      if (type == GameType.chess || type == GameType.checkers) {
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 4; x++) {
            if ((x + y).isOdd) {
              canvas.drawRect(
                Rect.fromLTWH(6 + x * 9, 6 + y * 9, 9, 9),
                Paint()..color = colors.primary.withValues(alpha: .16),
              );
            }
          }
        }
        if (type == GameType.checkers) {
          for (final p in [
            const Offset(19.5, 10.5),
            const Offset(37.5, 10.5),
            const Offset(10.5, 37.5),
          ]) {
            canvas.drawCircle(p, 3.5, stone);
          }
          canvas.drawCircle(const Offset(28.5, 28.5), 5, stone);
          canvas.drawCircle(
            const Offset(28.5, 28.5),
            2.5,
            Paint()..color = colors.primaryContainer,
          );
        } else {
          canvas.drawPath(
            Path()
              ..moveTo(15, 36)
              ..lineTo(17, 32)
              ..lineTo(19, 30)
              ..lineTo(17, 19)
              ..lineTo(24, 21)
              ..lineTo(31, 19)
              ..lineTo(29, 30)
              ..lineTo(31, 32)
              ..lineTo(33, 36)
              ..close(),
            stone,
          );
          canvas.drawLine(
            const Offset(24, 10),
            const Offset(24, 18),
            Paint()
              ..color = colors.primary
              ..strokeWidth = 2.5,
          );
          canvas.drawLine(
            const Offset(20, 13),
            const Offset(28, 13),
            Paint()
              ..color = colors.primary
              ..strokeWidth = 2.5,
          );
        }
      } else if (type == GameType.xiangqi) {
        for (var i = 0; i < 5; i++) {
          canvas.drawLine(
            Offset(7, 7 + i * 8.5),
            Offset(41, 7 + i * 8.5),
            line,
          );
          canvas.drawLine(
            Offset(7 + i * 8.5, 7),
            Offset(7 + i * 8.5, 20),
            line,
          );
          canvas.drawLine(
            Offset(7 + i * 8.5, 28),
            Offset(7 + i * 8.5, 41),
            line,
          );
        }
        canvas.drawLine(const Offset(15.5, 7), const Offset(32.5, 15.5), line);
        canvas.drawLine(const Offset(32.5, 7), const Offset(15.5, 15.5), line);
        canvas.drawCircle(const Offset(24, 7), 4, stone);
        canvas.drawCircle(
          const Offset(15.5, 32.5),
          4,
          Paint()..color = colors.tertiary,
        );
        canvas.drawCircle(
          const Offset(32.5, 41),
          4,
          Paint()..color = colors.tertiary,
        );
      } else {
        for (var i = 0; i < 5; i++) {
          canvas.drawLine(
            Offset(7, 7 + i * 8.5),
            Offset(41, 7 + i * 8.5),
            line,
          );
          canvas.drawLine(
            Offset(7 + i * 8.5, 7),
            Offset(7 + i * 8.5, 41),
            line,
          );
        }
        final points = type == GameType.gomoku
            ? [
                const Offset(15.5, 32.5),
                const Offset(24, 24),
                const Offset(32.5, 15.5),
              ]
            : [
                const Offset(15.5, 15.5),
                const Offset(24, 24),
                const Offset(15.5, 24),
              ];
        for (final point in points) {
          canvas.drawCircle(point, 4, stone);
        }
        canvas.drawCircle(
          const Offset(32.5, 32.5),
          4,
          Paint()..color = colors.onPrimary,
        );
        canvas.drawCircle(const Offset(32.5, 32.5), 4, line);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GameArtworkPainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.colors != colors;
}
