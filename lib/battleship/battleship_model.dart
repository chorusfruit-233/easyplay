const battleshipBoardSize = 10;
const battleshipRulesVersion = 2;
const battleshipFleetCells = 17;

bool battleshipInside(int cell) => cell >= 0 && cell < 100;

/// The clipped one-cell ring around a ship, including diagonal neighbours.
Set<int> battleshipShipHalo(Iterable<int> shipCells) {
  final cells = shipCells.toSet();
  if (cells.any((cell) => !battleshipInside(cell))) {
    throw ArgumentError('舰船坐标必须位于海域内');
  }
  final halo = <int>{};
  for (final cell in cells) {
    final row = cell ~/ battleshipBoardSize;
    final column = cell % battleshipBoardSize;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        final r = row + dr, c = column + dc;
        if (r >= 0 &&
            r < battleshipBoardSize &&
            c >= 0 &&
            c < battleshipBoardSize) {
          halo.add(r * battleshipBoardSize + c);
        }
      }
    }
  }
  return Set.unmodifiable(halo.difference(cells));
}

String battleshipCoordinate(int cell) {
  if (!battleshipInside(cell)) throw ArgumentError.value(cell, 'cell');
  return '${String.fromCharCode(65 + cell ~/ 10)}${cell % 10 + 1}';
}

enum BattleshipSeat {
  player1,
  player2;

  BattleshipSeat get opponent => values[1 - index];
  String get label => '玩家 ${index + 1}';
}

enum BattleshipPhase { placement, playing, finished }

enum ShipType {
  carrier,
  battleship,
  cruiser,
  submarine,
  destroyer;

  int get length => switch (this) {
    carrier => 5,
    battleship => 4,
    cruiser || submarine => 3,
    destroyer => 2,
  };
  String get label => switch (this) {
    carrier => '航母',
    battleship => '战列舰',
    cruiser => '巡洋舰',
    submarine => '潜艇',
    destroyer => '驱逐舰',
  };
}

enum ShipDirection { horizontal, vertical }

final class ShipPlacement {
  ShipPlacement(this.ship, this.start, this.direction)
    : cells = List.unmodifiable(_placementCells(ship, start, direction));

  final ShipType ship;
  final int start;
  final ShipDirection direction;
  final List<int> cells;

  Map<String, Object?> toWire() => Map.unmodifiable({
    'ship': ship.name,
    'start': start,
    'direction': direction.name,
  });

  factory ShipPlacement.fromWire(Map<String, Object?> wire) {
    _exactKeys(wire, const {'ship', 'start', 'direction'});
    try {
      return ShipPlacement(
        _named(ShipType.values, wire['ship']),
        _cell(wire['start']),
        _named(ShipDirection.values, wire['direction']),
      );
    } on ArgumentError {
      throw const FormatException('舰船位置越界');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ShipPlacement &&
      ship == other.ship &&
      start == other.start &&
      direction == other.direction;
  @override
  int get hashCode => Object.hash(ship, start, direction);
}

List<int> _placementCells(ShipType ship, int start, ShipDirection direction) {
  if (!battleshipInside(start) ||
      (direction == ShipDirection.horizontal
          ? start % 10 + ship.length > 10
          : start ~/ 10 + ship.length > 10)) {
    throw ArgumentError('舰船必须完整布置在 10×10 海域内');
  }
  return List.generate(
    ship.length,
    (i) => start + i * (direction == ShipDirection.horizontal ? 1 : 10),
  );
}

enum ShotOutcome {
  miss,
  hit,
  sunk;

  String get label => switch (this) {
    miss => '未命中',
    hit => '命中',
    sunk => '击沉',
  };
}

final class BattleshipShot {
  BattleshipShot({
    required this.attacker,
    required this.cell,
    required this.outcome,
    this.sunkShip,
    List<int> sunkCells = const [],
  }) : sunkCells = List.unmodifiable(sunkCells) {
    if (!battleshipInside(cell)) throw ArgumentError.value(cell, 'cell');
    if (outcome != ShotOutcome.sunk) {
      if (sunkShip != null || this.sunkCells.isNotEmpty) {
        throw ArgumentError('只有击沉结果可以公开舰船');
      }
    } else {
      final sorted = this.sunkCells.toList()..sort();
      if (sunkShip == null ||
          sorted.length != sunkShip!.length ||
          sorted.toSet().length != sorted.length ||
          !sorted.contains(cell) ||
          sorted.any((c) => !battleshipInside(c))) {
        throw ArgumentError('击沉舰船信息无效');
      }
      final direction = sorted.every((c) => c ~/ 10 == sorted.first ~/ 10)
          ? ShipDirection.horizontal
          : ShipDirection.vertical;
      final expected = _placementCells(sunkShip!, sorted.first, direction);
      if (!_sameCells(sorted, expected)) throw ArgumentError('舰船必须连续且笔直');
    }
  }

  final BattleshipSeat attacker;
  final int cell;
  final ShotOutcome outcome;
  final ShipType? sunkShip;
  final List<int> sunkCells;

  Map<String, Object?> toWire() => Map.unmodifiable({
    'attacker': attacker.index,
    'cell': cell,
    'outcome': outcome.name,
    'sunkShip': sunkShip?.name,
    'sunkCells': sunkCells,
  });

  factory BattleshipShot.fromWire(Map<String, Object?> wire) {
    _exactKeys(wire, const {
      'attacker',
      'cell',
      'outcome',
      'sunkShip',
      'sunkCells',
    });
    try {
      return BattleshipShot(
        attacker: _seat(wire['attacker']),
        cell: _cell(wire['cell']),
        outcome: _named(ShotOutcome.values, wire['outcome']),
        sunkShip: wire['sunkShip'] == null
            ? null
            : _named(ShipType.values, wire['sunkShip']),
        sunkCells: _list(wire['sunkCells'], maxLength: 5).map(_cell).toList(),
      );
    } on ArgumentError {
      throw const FormatException('开火结果无效');
    }
  }
}

/// Publicly inferred water around ships already sunk by these shots.
Set<int> battleshipExcludedCells(Iterable<BattleshipShot> shots) =>
    Set.unmodifiable({
      for (final shot in shots)
        if (shot.outcome == ShotOutcome.sunk)
          ...battleshipShipHalo(shot.sunkCells),
    });

/// A recipient's immutable state. Unhit enemy ships do not exist in this view.
final class BattleshipPlayerView {
  BattleshipPlayerView({
    required this.seat,
    required this.phase,
    required this.turn,
    this.winner,
    required List<bool> ready,
    required List<ShipPlacement> ownFleet,
    required List<BattleshipShot> shots,
    List<ShipPlacement> enemyFleet = const [],
  }) : ready = List.unmodifiable(ready),
       ownFleet = List.unmodifiable(ownFleet),
       shots = List.unmodifiable(shots),
       enemyFleet = List.unmodifiable(enemyFleet) {
    _validate();
  }

  final BattleshipSeat seat;
  final BattleshipPhase phase;
  final BattleshipSeat turn;
  final BattleshipSeat? winner;
  final List<bool> ready;
  final List<ShipPlacement> ownFleet, enemyFleet;
  final List<BattleshipShot> shots;

  bool get ownReady => ready[seat.index];
  bool get enemyReady => ready[seat.opponent.index];
  bool get isTurn => phase == BattleshipPhase.playing && turn == seat;
  Iterable<BattleshipShot> get outgoingShots =>
      shots.where((shot) => shot.attacker == seat);
  Iterable<BattleshipShot> get incomingShots =>
      shots.where((shot) => shot.attacker != seat);
  Set<int> get excludedCells => battleshipExcludedCells(outgoingShots);
  bool canFire(int cell) =>
      isTurn &&
      battleshipInside(cell) &&
      !excludedCells.contains(cell) &&
      !outgoingShots.any((shot) => shot.cell == cell);

  Map<String, Object?> toWire() => Map.unmodifiable({
    'seat': seat.index,
    'phase': phase.name,
    'turn': turn.index,
    'winner': winner?.index,
    'ready': ready,
    'ownFleet': List.unmodifiable(ownFleet.map((ship) => ship.toWire())),
    'enemyFleet': List.unmodifiable(enemyFleet.map((ship) => ship.toWire())),
    'shots': List.unmodifiable(shots.map((shot) => shot.toWire())),
  });

  factory BattleshipPlayerView.fromWire(Map<String, Object?> wire) {
    _exactKeys(wire, const {
      'seat',
      'phase',
      'turn',
      'winner',
      'ready',
      'ownFleet',
      'enemyFleet',
      'shots',
    });
    final ready = _list(wire['ready'], maxLength: 2);
    if (ready.length != 2 || ready.any((value) => value is! bool)) {
      throw const FormatException('舰队确认状态无效');
    }
    try {
      return BattleshipPlayerView(
        seat: _seat(wire['seat']),
        phase: _named(BattleshipPhase.values, wire['phase']),
        turn: _seat(wire['turn']),
        winner: wire['winner'] == null ? null : _seat(wire['winner']),
        ready: ready.cast<bool>(),
        ownFleet: _list(
          wire['ownFleet'],
          maxLength: ShipType.values.length,
        ).map((value) => ShipPlacement.fromWire(_map(value))).toList(),
        enemyFleet: _list(
          wire['enemyFleet'],
          maxLength: ShipType.values.length,
        ).map((value) => ShipPlacement.fromWire(_map(value))).toList(),
        shots: _list(
          wire['shots'],
          maxLength: 200,
        ).map((value) => BattleshipShot.fromWire(_map(value))).toList(),
      );
    } on ArgumentError {
      throw const FormatException('海战棋快照无效');
    }
  }

  void _validate() {
    if (ready.length != 2 || shots.length > 200) {
      throw ArgumentError('海战棋快照大小无效');
    }
    _validateFleet(ownFleet, complete: ownReady);
    if (phase == BattleshipPhase.placement) {
      if (winner != null || shots.isNotEmpty || ready.every((value) => value)) {
        throw ArgumentError('布阵阶段状态无效');
      }
    } else if (!ready.every((value) => value)) {
      throw ArgumentError('双方确认舰队后才能开战');
    }
    if (phase == BattleshipPhase.finished) {
      if (winner == null) throw ArgumentError('终局缺少获胜方');
      _validateFleet(enemyFleet, complete: true);
    } else if (enemyFleet.isNotEmpty || winner != null) {
      throw ArgumentError('不能提前公开敌方舰队或胜负');
    }
    final fired = <BattleshipSeat, Set<int>>{
      for (final player in BattleshipSeat.values) player: <int>{},
    };
    final hits = <BattleshipSeat, Set<int>>{
      for (final player in BattleshipSeat.values) player: <int>{},
    };
    final sunk = <BattleshipSeat, Set<ShipType>>{
      for (final player in BattleshipSeat.values) player: <ShipType>{},
    };
    final sunkCells = <BattleshipSeat, Set<int>>{
      for (final player in BattleshipSeat.values) player: <int>{},
    };
    final excluded = <BattleshipSeat, Set<int>>{
      for (final player in BattleshipSeat.values) player: <int>{},
    };
    BattleshipSeat? previous;
    for (var index = 0; index < shots.length; index++) {
      final shot = shots[index];
      if (shot.attacker == previous ||
          excluded[shot.attacker]!.contains(shot.cell) ||
          !fired[shot.attacker]!.add(shot.cell)) {
        throw ArgumentError('回合顺序、重复开火或已排除海域无效');
      }
      previous = shot.attacker;
      final knownFleet = shot.attacker != seat
          ? ownFleet
          : phase == BattleshipPhase.finished
          ? enemyFleet
          : null;
      if (knownFleet != null) {
        final ship = knownFleet
            .where((ship) => ship.cells.contains(shot.cell))
            .firstOrNull;
        final expected = ship == null
            ? ShotOutcome.miss
            : ship.cells.every(
                (cell) =>
                    cell == shot.cell || hits[shot.attacker]!.contains(cell),
              )
            ? ShotOutcome.sunk
            : ShotOutcome.hit;
        if (shot.outcome != expected ||
            expected == ShotOutcome.sunk &&
                (shot.sunkShip != ship!.ship ||
                    !_sameCells(shot.sunkCells, ship.cells))) {
          throw ArgumentError('开火结果与已知舰队不符');
        }
      }
      if (shot.outcome != ShotOutcome.miss) hits[shot.attacker]!.add(shot.cell);
      if (shot.outcome == ShotOutcome.sunk) {
        final halo = battleshipShipHalo(shot.sunkCells);
        if (!sunk[shot.attacker]!.add(shot.sunkShip!) ||
            !shot.sunkCells.every(hits[shot.attacker]!.contains) ||
            shot.sunkCells.any(sunkCells[shot.attacker]!.contains) ||
            halo.any(hits[shot.attacker]!.contains)) {
          throw ArgumentError('击沉结果缺少公开命中记录，或舰船重叠、相邻');
        }
        sunkCells[shot.attacker]!.addAll(shot.sunkCells);
        excluded[shot.attacker]!.addAll(halo);
      }
      if (hits[shot.attacker]!.length >= battleshipFleetCells &&
          (hits[shot.attacker]!.length != battleshipFleetCells ||
              index != shots.length - 1 ||
              phase != BattleshipPhase.finished ||
              winner != shot.attacker)) {
        throw ArgumentError('舰队全灭后必须立即终局');
      }
    }
    if (shots.isNotEmpty &&
        turn !=
            (hits[shots.last.attacker]!.length == battleshipFleetCells
                ? shots.last.attacker
                : shots.last.attacker.opponent)) {
      throw ArgumentError('开火后必须交换回合');
    }
  }
}

/// Pure placement preview with the same replacement and boundary rules as play.
bool canPlaceBattleshipAt(
  Iterable<ShipPlacement> fleet,
  ShipType ship,
  int start,
  ShipDirection direction,
) {
  try {
    final current = fleet.toList();
    _validateFleet(current, complete: false);
    final placement = ShipPlacement(ship, start, direction);
    _validateFleet([
      ...current.where((placed) => placed.ship != ship),
      placement,
    ], complete: false);
    return true;
  } on ArgumentError {
    return false;
  }
}

bool canPlaceBattleship(
  Iterable<ShipPlacement> fleet,
  ShipPlacement placement,
) => canPlaceBattleshipAt(
  fleet,
  placement.ship,
  placement.start,
  placement.direction,
);

void validateBattleshipFleet(
  Iterable<ShipPlacement> fleet, {
  bool complete = false,
}) => _validateFleet(fleet.toList(), complete: complete);

void _validateFleet(List<ShipPlacement> fleet, {required bool complete}) {
  final types = <ShipType>{};
  final blocked = <int>{};
  for (final placement in fleet) {
    if (!types.add(placement.ship) || placement.cells.any(blocked.contains)) {
      throw ArgumentError('舰船不能重复、重叠或相邻（包括斜角）');
    }
    blocked
      ..addAll(placement.cells)
      ..addAll(battleshipShipHalo(placement.cells));
  }
  if (complete && types.length != ShipType.values.length) {
    throw ArgumentError('请完整布置五艘舰船');
  }
}

bool _sameCells(Iterable<int> a, Iterable<int> b) {
  final left = a.toSet(), right = b.toSet();
  return left.length == right.length && left.containsAll(right);
}

T _named<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) throw const FormatException('枚举值无效');
  return values.where((value) => value.name == raw).firstOrNull ??
      (throw const FormatException('枚举值无效'));
}

BattleshipSeat _seat(Object? raw) {
  if (raw is! int || raw < 0 || raw > 1) {
    throw const FormatException('玩家座位无效');
  }
  return BattleshipSeat.values[raw];
}

int _cell(Object? raw) {
  if (raw is! int || !battleshipInside(raw)) {
    throw const FormatException('海域坐标无效');
  }
  return raw;
}

List<Object?> _list(Object? value, {required int maxLength}) {
  if (value is! List || value.length > maxLength) {
    throw const FormatException('列表无效或过长');
  }
  return value.cast<Object?>();
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('对象无效');
  }
  return Map<String, Object?>.from(value);
}

void _exactKeys(Map<String, Object?> wire, Set<String> keys) {
  if (wire.length != keys.length || !keys.containsAll(wire.keys)) {
    throw const FormatException('字段不完整或包含未知字段');
  }
}
