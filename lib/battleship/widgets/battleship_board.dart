import 'dart:math' as math;

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
    final excluded = battleshipExcludedCells(attacks);
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
      if (excluded.contains(cell)) return '已排除，击沉周边';
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
                          excluded: excluded,
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
                        child: _cell(
                          cell,
                          status(cell),
                          unavailable:
                              id == 'target' &&
                              (byCell.containsKey(cell) ||
                                  excluded.contains(cell)),
                        ),
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

  Widget _cell(int cell, String status, {required bool unavailable}) {
    final enabled =
        onCell != null && !unavailable && (canSelect?.call(cell) ?? true);
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
    required this.excluded,
    required this.selected,
    required this.preview,
    required this.previewValid,
  });

  final ColorScheme colors;
  final List<ShipPlacement> fleet;
  final List<BattleshipShot> shots;
  final Set<int> excluded;
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
    final fired = shots.map((shot) => shot.cell).toSet();
    for (final cell in excluded.difference(fired)) {
      final rect = cellRect(cell);
      canvas.drawRect(
        rect.deflate(.75),
        Paint()..color = colors.primary.withValues(alpha: .045),
      );
      canvas.drawCircle(
        rect.center,
        cellSize * .075,
        Paint()
          ..color = colors.onSurfaceVariant.withValues(alpha: .42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final visibleShips = {for (final ship in fleet) ship.ship: ship};
    final sunkTypes = <ShipType>{};
    for (final shot in shots) {
      if (shot.sunkShip case final type?) {
        sunkTypes.add(type);
        // A sunk result is public information, including on the enemy sea.
        // Reconstruct only this disclosed hull; never infer a hidden fleet.
        final cells = shot.sunkCells.toList()..sort();
        visibleShips.putIfAbsent(
          type,
          () => ShipPlacement(
            type,
            cells.first,
            cells[1] - cells.first == 1
                ? ShipDirection.horizontal
                : ShipDirection.vertical,
          ),
        );
      }
    }
    for (final placement in visibleShips.values) {
      _VesselPainter(colors).paint(
        canvas,
        placement,
        cellRect(placement.cells.first).topLeft,
        cellSize,
        sunk: sunkTypes.contains(placement.ship),
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
        // The light backing keeps every actual hit legible over either an
        // intact deck or a dark wreck, without replacing the ship silhouette.
        canvas.drawCircle(
          center,
          cellSize * .255,
          Paint()..color = colors.surface.withValues(alpha: .94),
        );
        canvas.drawCircle(
          center,
          cellSize * .255,
          Paint()
            ..color = colors.error.withValues(alpha: .65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
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

/// Draws in cell units with the bow facing right. Rotating this single plan
/// keeps the deck, bow, and fittings aligned for both legal orientations.
class _VesselPainter {
  _VesselPainter(this.colors);

  final ColorScheme colors;

  Color get _edge => Color.lerp(colors.primary, colors.onSurface, .62)!;
  Color get _deck =>
      Color.lerp(colors.primaryContainer, colors.surfaceContainerHighest, .6)!;
  Color get _raised =>
      Color.lerp(colors.primaryContainer, colors.surface, .65)!;

  void paint(
    Canvas canvas,
    ShipPlacement placement,
    Offset origin,
    double cellSize, {
    required bool sunk,
  }) {
    final length = placement.ship.length.toDouble();
    final type = placement.ship;
    final beam = switch (type) {
      ShipType.carrier => .76,
      ShipType.submarine => .46,
      ShipType.destroyer => .56,
      _ => .66,
    };
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    if (placement.direction == ShipDirection.vertical) {
      canvas.translate(cellSize, 0);
      canvas.rotate(math.pi / 2);
    }
    canvas.scale(cellSize);
    // Fins, shadows, and gun barrels all stay inside occupied grid cells.
    canvas.clipRect(Rect.fromLTWH(0, 0, length, 1));
    final hull = _hull(length, beam);
    if (type == ShipType.submarine) {
      final fins = Path()
        ..moveTo(.28, .5)
        ..lineTo(.46, .17)
        ..lineTo(.64, .17)
        ..lineTo(.57, .5)
        ..lineTo(.64, .83)
        ..lineTo(.46, .83)
        ..close();
      canvas.drawPath(fins, Paint()..color = _edge);
    }
    canvas.drawPath(
      hull.shift(const Offset(0, .045)),
      Paint()
        ..color = colors.onSurface.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .07,
    );
    canvas.drawPath(
      hull,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_raised, _deck, colors.primary.withValues(alpha: .72)],
        ).createShader(Rect.fromLTWH(0, .1, length, .8)),
    );
    canvas.drawPath(
      hull,
      Paint()
        ..color = _edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = .035,
    );
    final deck = _hull(length, beam, inset: .075);
    canvas.drawPath(deck, Paint()..color = _deck);
    canvas.drawPath(
      deck,
      Paint()
        ..color = _raised.withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .022,
    );
    switch (type) {
      case ShipType.carrier:
        _carrier(canvas, length, deck);
      case ShipType.battleship:
        _structure(canvas, length * .52, .54, .43);
        _funnel(canvas, length * .43);
        _turret(canvas, .64, forward: false, twin: true);
        _turret(canvas, length - 1.16, twin: true);
        _turret(canvas, length - .59, twin: true);
      case ShipType.cruiser:
        _structure(canvas, length * .55, .57, .37);
        _funnel(canvas, length * .38);
        _turret(canvas, .5, forward: false);
        _turret(canvas, length - .57);
      case ShipType.submarine:
        _submarine(canvas, length);
      case ShipType.destroyer:
        _structure(canvas, .98, .48, .34);
        _funnel(canvas, .66);
        _turret(canvas, length - .48);
        for (final y in [.41, .59]) {
          _line(canvas, Offset(.26, y), Offset(.47, y), _edge, .055);
        }
    }
    if (sunk) {
      canvas.save();
      canvas.clipPath(hull);
      canvas.drawPath(
        hull,
        Paint()..color = colors.error.withValues(alpha: .19),
      );
      for (var cell = 0; cell < placement.ship.length; cell++) {
        final crack = Path()
          ..moveTo(cell + .25, .27)
          ..lineTo(cell + .37, .39)
          ..lineTo(cell + .29, .49)
          ..lineTo(cell + .4, .64)
          ..lineTo(cell + .34, .76);
        canvas.drawPath(
          crack,
          Paint()
            ..color = _edge.withValues(alpha: .8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .035,
        );
      }
      canvas.restore();
      canvas.drawPath(
        hull,
        Paint()
          ..color = colors.error.withValues(alpha: .8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .04,
      );
    }
    canvas.restore();
  }

  Path _hull(double length, double beam, {double inset = 0}) {
    final stern = .12 + inset;
    final bow = length - .1 - inset;
    final top = (1 - beam) / 2 + inset;
    final bottom = 1 - top;
    return Path()
      ..moveTo(stern, top + .13)
      ..quadraticBezierTo(stern, top, stern + .19, top)
      ..lineTo(bow - .56, top)
      ..cubicTo(bow - .3, top, bow - .08, .38, bow, .5)
      ..cubicTo(bow - .08, .62, bow - .3, bottom, bow - .56, bottom)
      ..lineTo(stern + .19, bottom)
      ..quadraticBezierTo(stern, bottom, stern, bottom - .13)
      ..close();
  }

  void _carrier(Canvas canvas, double length, Path deck) {
    canvas.drawPath(
      deck,
      Paint()..color = Color.lerp(colors.primary, colors.onSurface, .6)!,
    );
    final ink = colors.surface.withValues(alpha: .88);
    final runway = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = .022;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(.4, .28, length - .74, .51),
        const Radius.circular(.025),
      ),
      runway,
    );
    for (var x = .58; x < length - .9; x += .4) {
      _line(canvas, Offset(x, .395), Offset(x + .2, .395), ink, .025);
    }
    _line(canvas, const Offset(.43, .69), Offset(length - 1.1, .55), ink, .025);
    _line(canvas, const Offset(.44, .6), Offset(length - 1.1, .48), ink, .018);
    // The island is offset to starboard, leaving the flight deck continuous.
    _block(canvas, Rect.fromLTWH(length * .59, .6, .78, .17), _raised);
    _block(canvas, Rect.fromLTWH(length * .64, .57, .26, .16), _deck);
    _line(
      canvas,
      Offset(length * .67, .57),
      Offset(length * .67, .48),
      ink,
      .025,
    );
    for (final x in [1.2, 2.1]) {
      final plane = Path()
        ..moveTo(x + .18, .61)
        ..lineTo(x + .02, .65)
        ..lineTo(x - .08, .74)
        ..lineTo(x - .12, .74)
        ..lineTo(x - .08, .64)
        ..lineTo(x - .18, .62)
        ..lineTo(x - .18, .59)
        ..lineTo(x - .08, .58)
        ..lineTo(x - .12, .49)
        ..lineTo(x - .08, .49)
        ..lineTo(x + .02, .58)
        ..close();
      canvas.drawPath(plane, Paint()..color = ink);
    }
  }

  void _structure(Canvas canvas, double x, double width, double height) {
    _block(
      canvas,
      Rect.fromCenter(center: Offset(x, .5), width: width, height: height),
      _raised,
    );
    _block(
      canvas,
      Rect.fromCenter(
        center: Offset(x + width * .16, .5),
        width: width * .48,
        height: height * .67,
      ),
      _deck,
    );
    _line(
      canvas,
      Offset(x + width * .4, .5 - height * .2),
      Offset(x + width * .4, .5 + height * .2),
      colors.primary,
      .045,
    );
    _line(canvas, Offset(x - .07, .45), Offset(x - .07, .55), _edge, .025);
    _line(canvas, Offset(x - .12, .5), Offset(x + .03, .5), _edge, .025);
  }

  void _funnel(Canvas canvas, double x) {
    _block(
      canvas,
      Rect.fromCenter(center: Offset(x, .5), width: .19, height: .25),
      _edge,
    );
    _line(canvas, Offset(x - .025, .42), Offset(x - .025, .58), _deck, .04);
  }

  void _turret(
    Canvas canvas,
    double x, {
    bool forward = true,
    bool twin = false,
  }) {
    final end = x + (forward ? .34 : -.34);
    for (final y in twin ? [.445, .555] : [.5]) {
      _line(canvas, Offset(x, y), Offset(end, y), _edge, .052);
      _line(canvas, Offset(x, y - .012), Offset(end, y - .012), _raised, .016);
    }
    _block(
      canvas,
      Rect.fromCenter(center: Offset(x, .5), width: .27, height: .28),
      _raised,
    );
  }

  void _submarine(Canvas canvas, double length) {
    _line(canvas, const Offset(.16, .38), const Offset(.16, .62), _edge, .035);
    _block(canvas, Rect.fromLTWH(length * .44, .36, .52, .28), _edge);
    _block(canvas, Rect.fromLTWH(length * .46, .39, .35, .22), _deck);
    _line(
      canvas,
      Offset(length * .53, .42),
      Offset(length * .53, .29),
      _edge,
      .035,
    );
    _line(
      canvas,
      Offset(length * .53, .29),
      Offset(length * .53 + .11, .29),
      _edge,
      .035,
    );
    _line(
      canvas,
      Offset(length - .55, .4),
      Offset(length - .55, .6),
      _raised,
      .035,
    );
  }

  void _block(Canvas canvas, Rect rect, Color fill) {
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(.045));
    canvas.drawRRect(shape, Paint()..color = fill);
    canvas.drawRRect(
      shape,
      Paint()
        ..color = _edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = .025,
    );
  }

  void _line(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double width,
  ) {
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }
}
