import 'dart:math';

import 'battleship_model.dart';

/// Estimates remaining ship placements from public shot results alone.
///
/// Hits narrow the search to the most likely continuation of a damaged ship.
/// Sinking a ship removes its exact cells; neighbours remain possible because
/// the classic fleet placement rules allow different ships to touch.
class BattleshipAi {
  BattleshipAi({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  int choose(BattleshipPlayerView view) {
    if (view.phase != BattleshipPhase.playing || !view.isTurn) {
      throw StateError('当前不是 AI 的开火回合');
    }
    final shots = view.outgoingShots.toList();
    final fired = shots.map((shot) => shot.cell).toSet();
    final sunk = shots
        .where((shot) => shot.outcome == ShotOutcome.sunk)
        .toList();
    final sunkTypes = sunk.map((shot) => shot.sunkShip).toSet();
    final sunkCells = sunk.expand((shot) => shot.sunkCells).toSet();
    final blocked = {
      ...sunkCells,
      ...shots
          .where((shot) => shot.outcome == ShotOutcome.miss)
          .map((shot) => shot.cell),
    };
    final damaged = shots
        .where((shot) => shot.outcome == ShotOutcome.hit)
        .map((shot) => shot.cell)
        .where((cell) => !sunkCells.contains(cell))
        .toSet();
    final available = [
      for (
        var cell = 0;
        cell < battleshipBoardSize * battleshipBoardSize;
        cell++
      )
        if (!fired.contains(cell)) cell,
    ];
    if (available.isEmpty) throw StateError('没有尚未开火的位置');

    final hunt = List<int>.filled(100, 0);
    var target = List<int>.filled(100, 0);
    var strongestEvidence = 0;
    for (final ship in ShipType.values) {
      if (sunkTypes.contains(ship)) continue;
      for (final direction in ShipDirection.values) {
        for (var start = 0; start < 100; start++) {
          final row = start ~/ battleshipBoardSize;
          final column = start % battleshipBoardSize;
          if (direction == ShipDirection.horizontal
              ? column + ship.length > battleshipBoardSize
              : row + ship.length > battleshipBoardSize) {
            continue;
          }
          final step = direction == ShipDirection.horizontal
              ? 1
              : battleshipBoardSize;
          final cells = [
            for (var i = 0; i < ship.length; i++) start + i * step,
          ];
          if (cells.any(blocked.contains)) continue;
          final unknown = cells.where((cell) => !fired.contains(cell)).toList();
          if (unknown.isEmpty) continue;
          final evidence = cells.where(damaged.contains).length;
          if (evidence == 0) {
            for (final cell in unknown) {
              hunt[cell]++;
            }
          } else {
            if (evidence > strongestEvidence) {
              strongestEvidence = evidence;
              target = List<int>.filled(100, 0);
            }
            if (evidence == strongestEvidence) {
              for (final cell in unknown) {
                target[cell]++;
              }
            }
          }
        }
      }
    }
    final scores = strongestEvidence > 0 ? target : hunt;
    final bestScore = available.map((cell) => scores[cell]).reduce(max);
    final best = available.where((cell) => scores[cell] == bestScore).toList();
    return best[_random.nextInt(best.length)];
  }
}
