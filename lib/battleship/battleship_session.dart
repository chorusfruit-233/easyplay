import 'dart:math';

import 'battleship_model.dart';

/// Authority-owned rules state. Send view(seat), never the whole authority.
class BattleshipSession {
  BattleshipSession({
    Random? random,
    BattleshipSeat first = BattleshipSeat.player1,
  }) : _random = random ?? Random.secure(),
       _first = first,
       _turn = first;

  final Random _random;
  BattleshipSeat _first, _turn;
  BattleshipPhase _phase = BattleshipPhase.placement;
  BattleshipSeat? _winner;
  final _fleets = <BattleshipSeat, Map<ShipType, ShipPlacement>>{
    for (final seat in BattleshipSeat.values) seat: {},
  };
  final _ready = <BattleshipSeat>{};
  final _shots = <BattleshipShot>[];
  int _revision = 0;

  BattleshipPhase get phase => _phase;
  BattleshipSeat get turn => _turn;
  BattleshipSeat? get winner => _winner;
  int get revision => _revision;

  BattleshipPlayerView view(BattleshipSeat seat) => BattleshipPlayerView(
    seat: seat,
    phase: _phase,
    turn: _turn,
    winner: _winner,
    ready: [
      for (final player in BattleshipSeat.values) _ready.contains(player),
    ],
    ownFleet: _orderedFleet(seat),
    enemyFleet: _phase == BattleshipPhase.finished
        ? _orderedFleet(seat.opponent)
        : const [],
    shots: _shots,
  );

  List<ShipPlacement> _orderedFleet(BattleshipSeat seat) => [
    for (final ship in ShipType.values) ?_fleets[seat]![ship],
  ];

  void _canPlace(BattleshipSeat seat) {
    if (_phase != BattleshipPhase.placement || _ready.contains(seat)) {
      throw StateError('舰队已确认，不能修改布阵');
    }
  }

  void place(BattleshipSeat seat, ShipPlacement placement) {
    _canPlace(seat);
    final next = Map<ShipType, ShipPlacement>.of(_fleets[seat]!);
    next[placement.ship] = placement;
    validateBattleshipFleet(next.values);
    _fleets[seat]!
      ..clear()
      ..addAll(next);
    _revision++;
  }

  void remove(BattleshipSeat seat, ShipType ship) {
    _canPlace(seat);
    if (_fleets[seat]!.remove(ship) == null) throw StateError('尚未布置这艘舰船');
    _revision++;
  }

  void clearFleet(BattleshipSeat seat) {
    _canPlace(seat);
    _fleets[seat]!.clear();
    _revision++;
  }

  void randomizeFleet(BattleshipSeat seat) {
    _canPlace(seat);
    final next = <ShipType, ShipPlacement>{};
    final occupied = <int>{};
    for (final ship in ShipType.values) {
      final candidates = <ShipPlacement>[];
      for (var start = 0; start < 100; start++) {
        for (final direction in ShipDirection.values) {
          if (direction == ShipDirection.horizontal
              ? start % 10 + ship.length <= 10
              : start ~/ 10 + ship.length <= 10) {
            final placement = ShipPlacement(ship, start, direction);
            if (!placement.cells.any(occupied.contains)) {
              candidates.add(placement);
            }
          }
        }
      }
      // Seventeen occupied cells cannot cover every placement on a 10x10 sea.
      final placement = candidates[_random.nextInt(candidates.length)];
      next[ship] = placement;
      occupied.addAll(placement.cells);
    }
    _fleets[seat]!
      ..clear()
      ..addAll(next);
    _revision++;
  }

  void ready(BattleshipSeat seat) {
    _canPlace(seat);
    validateBattleshipFleet(_fleets[seat]!.values, complete: true);
    _ready.add(seat);
    if (_ready.length == 2) {
      _phase = BattleshipPhase.playing;
      _turn = _first;
    }
    _revision++;
  }

  BattleshipShot fire(BattleshipSeat seat, int cell) {
    if (_phase != BattleshipPhase.playing || seat != _turn) {
      throw StateError('请等待自己的开火回合');
    }
    if (!battleshipInside(cell)) throw ArgumentError.value(cell, 'cell');
    if (_shots.any((shot) => shot.attacker == seat && shot.cell == cell)) {
      throw StateError('该海域已经开火，请选择其他位置');
    }
    final hits = _shots
        .where(
          (shot) => shot.attacker == seat && shot.outcome != ShotOutcome.miss,
        )
        .map((shot) => shot.cell)
        .toSet();
    final ship = _fleets[seat.opponent]!.values
        .where((ship) => ship.cells.contains(cell))
        .firstOrNull;
    final sunk =
        ship != null && ship.cells.every((c) => c == cell || hits.contains(c));
    final shot = BattleshipShot(
      attacker: seat,
      cell: cell,
      outcome: ship == null
          ? ShotOutcome.miss
          : sunk
          ? ShotOutcome.sunk
          : ShotOutcome.hit,
      sunkShip: sunk ? ship.ship : null,
      sunkCells: sunk ? ship.cells : const [],
    );
    _shots.add(shot);
    if (ship != null && hits.length + 1 == battleshipFleetCells) {
      _phase = BattleshipPhase.finished;
      _winner = seat;
    } else {
      _turn = seat.opponent;
    }
    _revision++;
    return shot;
  }

  void resign(BattleshipSeat seat) {
    if (_phase != BattleshipPhase.playing) throw StateError('开战后才能认输');
    _phase = BattleshipPhase.finished;
    _winner = seat.opponent;
    _revision++;
  }

  void reset({BattleshipSeat? first}) {
    _first = first ?? _first.opponent;
    _turn = _first;
    _phase = BattleshipPhase.placement;
    _winner = null;
    _ready.clear();
    _shots.clear();
    for (final fleet in _fleets.values) {
      fleet.clear();
    }
    _revision++;
  }
}
