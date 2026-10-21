import 'package:flutter/material.dart';

import '../battleship_model.dart';

/// A visible sea and its public attack marks. The caller supplies only the
/// fleet this viewer is entitled to see.
class BattleshipBoard extends StatelessWidget {
  const BattleshipBoard({
    super.key,
    required this.id,
    required this.label,
    this.fleet = const [],
    this.shots = const [],
    this.selected,
    this.preview = const [],
    this.previewValid = true,
    this.onCell,
    this.canSelect,
  });

  final String id;
  final String label;
  final List<ShipPlacement> fleet;
  final Iterable<BattleshipShot> shots;
  final int? selected;
  final List<int> preview;
  final bool previewValid;
  final ValueChanged<int>? onCell;
  final bool Function(int)? canSelect;

  static const _rail = 24.0;

  @override
  Widget build(BuildContext context) {
    final attacks = shots.toList(growable: false);
    final byCell = {for (final shot in attacks) shot.cell: shot};
    final sunk = <int, ShipType>{
      for (final shot in attacks)
        if (shot.sunkShip != null)
          for (final cell in shot.sunkCells) cell: shot.sunkShip!,
    };
    final vessels = <int, ShipType>{
      for (final placement in fleet)
        for (final cell in placement.cells) cell: placement.ship,
    };
    String status(int cell) {
      if (sunk[cell] case final ship?) return '已击沉${ship.label}';
      if (byCell[cell] case final shot?) {
        return shot.outcome == ShotOutcome.miss ? '未命中' : '命中';
      }
      if (preview.contains(cell)) {
        return previewValid ? '布阵预览' : '不可放置';
      }
      if (vessels[cell] case final ship?) return ship.label;
      return id == 'target' ? '未侦察' : '海面';
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellSize = (constraints.maxWidth - _rail) / 10;
              return SizedBox.expand(
                key: ValueKey('battleship-$id-board'),
                child: Stack(
                  textDirection: TextDirection.ltr,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SeaPainter(
                          colors: Theme.of(context).colorScheme,
                          fleet: fleet,
                          shots: attacks,
                          selected: selected,
                          preview: preview,
                          previewValid: previewValid,
                        ),
                      ),
                    ),
                    for (var cell = 0; cell < 100; cell++)
                      Positioned(
                        left: _rail + cell % 10 * cellSize,
                        top: _rail + cell ~/ 10 * cellSize,
                        width: cellSize,
                        height: cellSize,
                        child: _cell(cell, status(cell)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _cell(int cell, String status) {
    final enabled = onCell != null && (canSelect?.call(cell) ?? true);
    void activate() => onCell!(cell);
    return Semantics(
      key: ValueKey('battleship-$id-cell-$cell'),
      label: '$label ${battleshipCoordinate(cell)} $status',
      button: onCell != null,
      enabled: onCell == null ? null : enabled,
      selected: selected == null ? null : selected == cell,
      onTap: enabled ? activate : null,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? activate : null,
            canRequestFocus: enabled,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _SeaPainter extends CustomPainter {
  _SeaPainter({
    required this.colors,
    required this.fleet,
    required this.shots,
    required this.selected,
    required this.preview,
    required this.previewValid,
  });

  final ColorScheme colors;
  final List<ShipPlacement> fleet;
  final List<BattleshipShot> shots;
  final int? selected;
  final List<int> preview;
  final bool previewValid;

  @override
  void paint(Canvas canvas, Size size) {
    const rail = BattleshipBoard._rail;
    final cellSize = (size.width - rail) / 10;
    final sea = Rect.fromLTWH(rail, rail, cellSize * 10, cellSize * 10);
    final border = Paint()
      ..color = colors.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75;
    canvas.drawRRect(
      RRect.fromRectAndRadius(sea, const Radius.circular(6)),
      Paint()..color = colors.surfaceContainerLow,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(sea, const Radius.circular(6)));
    for (var i = 0; i <= 10; i++) {
      canvas.drawLine(
        Offset(rail + i * cellSize, rail),
        Offset(rail + i * cellSize, sea.bottom),
        border,
      );
      canvas.drawLine(
        Offset(rail, rail + i * cellSize),
        Offset(sea.right, rail + i * cellSize),
        border,
      );
    }
    Rect cellRect(int cell) => Rect.fromLTWH(
      rail + cell % 10 * cellSize,
      rail + cell ~/ 10 * cellSize,
      cellSize,
      cellSize,
    );
    for (final placement in fleet) {
      final cells = placement.cells;
      if (cells.isEmpty) continue;
      final ship = cellRect(cells.first).expandToInclude(cellRect(cells.last));
      final shape = RRect.fromRectAndRadius(
        ship.deflate(cellSize * .13),
        Radius.circular(cellSize * .25),
      );
      canvas.drawRRect(shape, Paint()..color = colors.primaryContainer);
      canvas.drawRRect(
        shape,
        Paint()
          ..color = colors.primary.withValues(alpha: .7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      final center = ship.center;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: placement.direction == ShipDirection.horizontal
                ? cellSize * .65
                : cellSize * .28,
            height: placement.direction == ShipDirection.vertical
                ? cellSize * .65
                : cellSize * .28,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = colors.primary.withValues(alpha: .6),
      );
    }
    final sunk = shots.expand((shot) => shot.sunkCells).toSet();
    for (final cell in sunk) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect(cell).deflate(1.5),
          const Radius.circular(3),
        ),
        Paint()..color = colors.errorContainer,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect(cell).deflate(1.5),
          const Radius.circular(3),
        ),
        Paint()
          ..color = colors.error
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
    for (final shot in shots) {
      final center = cellRect(shot.cell).center;
      if (shot.outcome == ShotOutcome.miss) {
        canvas.drawCircle(
          center,
          cellSize * .12,
          Paint()..color = colors.onSurfaceVariant,
        );
        canvas.drawCircle(
          center,
          cellSize * .24,
          Paint()
            ..color = colors.onSurfaceVariant.withValues(alpha: .5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      } else {
        final mark = Paint()
          ..color = colors.error
          ..strokeWidth = cellSize * .085
          ..strokeCap = StrokeCap.round;
        final distance = cellSize * .19;
        canvas.drawLine(
          center - Offset(distance, distance),
          center + Offset(distance, distance),
          mark,
        );
        canvas.drawLine(
          center + Offset(-distance, distance),
          center + Offset(distance, -distance),
          mark,
        );
      }
    }
    if (shots.isNotEmpty) {
      final last = cellRect(shots.last.cell).deflate(1.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(last, const Radius.circular(3)),
        Paint()
          ..color = colors.tertiary
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    final previewColor = previewValid ? colors.primary : colors.error;
    for (final cell in preview.where((cell) => cell >= 0 && cell < 100)) {
      canvas.drawRect(
        cellRect(cell).deflate(1),
        Paint()..color = previewColor.withValues(alpha: .23),
      );
      canvas.drawRect(
        cellRect(cell).deflate(2),
        Paint()
          ..color = previewColor
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
    if (selected case final cell? when cell >= 0 && cell < 100) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect(cell).deflate(2),
          const Radius.circular(3),
        ),
        Paint()
          ..color = colors.primary
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(sea.deflate(.4), const Radius.circular(6)),
      border,
    );
    for (var i = 0; i < 10; i++) {
      _label(canvas, '${i + 1}', Offset(rail + (i + .5) * cellSize, rail / 2));
      _label(
        canvas,
        String.fromCharCode(65 + i),
        Offset(rail / 2, rail + (i + .5) * cellSize),
      );
    }
  }

  void _label(Canvas canvas, String value, Offset center) {
    final text = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(covariant _SeaPainter oldDelegate) => true;
}
