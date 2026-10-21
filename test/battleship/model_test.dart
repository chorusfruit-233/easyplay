import 'dart:convert';

import 'package:easyplay/battleship/battleship_model.dart';
import 'package:easyplay/battleship/battleship_session.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> copy(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

BattleshipSession readyGame() {
  final game = BattleshipSession();
  for (final seat in BattleshipSeat.values) {
    for (final ship in ShipType.values) {
      game.place(
        seat,
        ShipPlacement(ship, ship.index * 10, ShipDirection.horizontal),
      );
    }
    game.ready(seat);
  }
  return game;
}

void main() {
  test('coordinate labels include every edge without row wrapping', () {
    expect(battleshipCoordinate(0), 'A1');
    expect(battleshipCoordinate(9), 'A10');
    expect(battleshipCoordinate(10), 'B1');
    expect(battleshipCoordinate(99), 'J10');
    expect(() => battleshipCoordinate(-1), throwsArgumentError);
    expect(() => battleshipCoordinate(100), throwsArgumentError);
  });

  test(
    'ship and sunk-shot wire formats reject impossible geometry and hidden identities on hits',
    () {
      for (final start in [-1, 100, 8]) {
        expect(
          () => ShipPlacement.fromWire({
            'ship': 'carrier',
            'start': start,
            'direction': 'horizontal',
          }),
          throwsFormatException,
        );
      }
      expect(
        () => ShipPlacement.fromWire({
          'ship': 'carrier',
          'start': 0,
          'direction': 'diagonal',
        }),
        throwsFormatException,
      );
      expect(
        () => ShipPlacement.fromWire({
          'ship': 'carrier',
          'start': 0,
          'direction': 'horizontal',
          'secret': true,
        }),
        throwsFormatException,
      );
      expect(
        () => BattleshipShot(
          attacker: BattleshipSeat.player1,
          cell: 0,
          outcome: ShotOutcome.hit,
          sunkShip: ShipType.carrier,
        ),
        throwsArgumentError,
      );
      expect(
        () => BattleshipShot(
          attacker: BattleshipSeat.player1,
          cell: 0,
          outcome: ShotOutcome.sunk,
          sunkShip: ShipType.destroyer,
          sunkCells: [0, 11],
        ),
        throwsArgumentError,
      );
      expect(
        () => BattleshipShot(
          attacker: BattleshipSeat.player1,
          cell: 9,
          outcome: ShotOutcome.sunk,
          sunkShip: ShipType.destroyer,
          sunkCells: [9, 10],
        ),
        throwsArgumentError,
      );
      final shot = BattleshipShot(
        attacker: BattleshipSeat.player1,
        cell: 10,
        outcome: ShotOutcome.sunk,
        sunkShip: ShipType.destroyer,
        sunkCells: [0, 10],
      );
      expect(BattleshipShot.fromWire(shot.toWire()).toWire(), shot.toWire());
    },
  );

  test(
    'view owns immutable copies of every fleet, readiness and history collection',
    () {
      final game = readyGame();
      final old = game.view(BattleshipSeat.player1);
      expect(() => old.ready[0] = false, throwsUnsupportedError);
      expect(() => old.ownFleet.clear(), throwsUnsupportedError);
      expect(() => old.ownFleet.first.cells.add(99), throwsUnsupportedError);
      expect(
        () => old.shots.add(
          BattleshipShot(
            attacker: BattleshipSeat.player1,
            cell: 99,
            outcome: ShotOutcome.miss,
          ),
        ),
        throwsUnsupportedError,
      );
      final wire = old.toWire();
      expect(() => wire['secret'] = true, throwsUnsupportedError);
      expect(() => (wire['ownFleet'] as List).clear(), throwsUnsupportedError);
      expect(
        () => ((wire['ownFleet'] as List).first as Map)['start'] = 99,
        throwsUnsupportedError,
      );
      final sunk = BattleshipShot(
        attacker: BattleshipSeat.player1,
        cell: 1,
        outcome: ShotOutcome.sunk,
        sunkShip: ShipType.destroyer,
        sunkCells: [0, 1],
      );
      expect(() => sunk.sunkCells.clear(), throwsUnsupportedError);
      expect(
        () => (sunk.toWire()['sunkCells'] as List).clear(),
        throwsUnsupportedError,
      );
      game.fire(BattleshipSeat.player1, 0);
      expect(old.shots, isEmpty);
      expect(old.turn, BattleshipSeat.player1);
      expect(game.view(BattleshipSeat.player1).turn, BattleshipSeat.player2);
    },
  );

  test(
    'wire snapshots have no opponent placement, seeds, or unhit ship identity',
    () {
      final game = readyGame();
      game.fire(BattleshipSeat.player1, 0);
      final view = game.view(BattleshipSeat.player1);
      final wire = view.toWire();
      expect(
        wire.keys,
        unorderedEquals([
          'seat',
          'phase',
          'turn',
          'winner',
          'ready',
          'ownFleet',
          'enemyFleet',
          'shots',
        ]),
      );
      expect(wire['enemyFleet'], isEmpty);
      expect((wire['shots'] as List).single, {
        'attacker': 0,
        'cell': 0,
        'outcome': 'hit',
        'sunkShip': null,
        'sunkCells': [],
      });
      expect(BattleshipPlayerView.fromWire(copy(wire)).toWire(), wire);
      final leaked = copy(wire)
        ..['enemyFleet'] = game
            .view(BattleshipSeat.player2)
            .ownFleet
            .map((ship) => ship.toWire())
            .toList();
      expect(
        () => BattleshipPlayerView.fromWire(leaked),
        throwsFormatException,
      );
      final unknown = copy(wire)..['seed'] = 12;
      expect(
        () => BattleshipPlayerView.fromWire(unknown),
        throwsFormatException,
      );
    },
  );

  test(
    'strict snapshots reject malformed types, readiness, fleets, phases and turn',
    () {
      final base = readyGame().view(BattleshipSeat.player1).toWire();
      for (final (key, value) in <(String, Object?)>[
        ('seat', -1),
        ('seat', 2),
        ('turn', '0'),
        ('phase', 'unknown'),
        ('ready', [true]),
        ('ready', [true, 1]),
        ('ready', [true, false]),
        ('winner', 1),
        ('ownFleet', []),
        ('phase', 'finished'),
        ('phase', 'placement'),
      ]) {
        final bad = copy(base)..[key] = value;
        expect(
          () => BattleshipPlayerView.fromWire(bad),
          throwsFormatException,
          reason: '$key=$value',
        );
      }
      final duplicate = copy(base);
      final fleet = duplicate['ownFleet'] as List;
      fleet[4] = fleet[0];
      expect(
        () => BattleshipPlayerView.fromWire(duplicate),
        throwsFormatException,
      );
      final overlap = copy(base);
      ((overlap['ownFleet'] as List)[1] as Map)['start'] = 1;
      expect(
        () => BattleshipPlayerView.fromWire(overlap),
        throwsFormatException,
      );
    },
  );

  test(
    'strict history rejects fabricated incoming outcomes, repeats and nonalternating turns',
    () {
      final game = readyGame();
      game.fire(BattleshipSeat.player1, 99);
      game.fire(BattleshipSeat.player2, 0);
      final base = game.view(BattleshipSeat.player1).toWire();
      final falseMiss = copy(base);
      ((falseMiss['shots'] as List)[1] as Map)['outcome'] = 'miss';
      expect(
        () => BattleshipPlayerView.fromWire(falseMiss),
        throwsFormatException,
      );
      final turn = copy(base)..['turn'] = 1;
      expect(() => BattleshipPlayerView.fromWire(turn), throwsFormatException);
      final order = copy(base);
      ((order['shots'] as List)[1] as Map)['attacker'] = 0;
      expect(() => BattleshipPlayerView.fromWire(order), throwsFormatException);
      final repeated = copy(base);
      (repeated['shots'] as List).add((repeated['shots'] as List).first);
      expect(
        () => BattleshipPlayerView.fromWire(repeated),
        throwsFormatException,
      );
      final fakeSunk = copy(base);
      final shot = (fakeSunk['shots'] as List)[0] as Map;
      shot['outcome'] = 'sunk';
      shot['sunkShip'] = 'destroyer';
      shot['sunkCells'] = [98, 99];
      expect(
        () => BattleshipPlayerView.fromWire(fakeSunk),
        throwsFormatException,
      );
    },
  );

  test('public sunk ships cannot reuse a previously sunk ship cell', () {
    final wire = copy(readyGame().view(BattleshipSeat.player1).toWire());
    wire['turn'] = 1;
    wire['shots'] = [
      BattleshipShot(
        attacker: BattleshipSeat.player1,
        cell: 0,
        outcome: ShotOutcome.hit,
      ).toWire(),
      BattleshipShot(
        attacker: BattleshipSeat.player2,
        cell: 99,
        outcome: ShotOutcome.miss,
      ).toWire(),
      BattleshipShot(
        attacker: BattleshipSeat.player1,
        cell: 1,
        outcome: ShotOutcome.sunk,
        sunkShip: ShipType.destroyer,
        sunkCells: [0, 1],
      ).toWire(),
      BattleshipShot(
        attacker: BattleshipSeat.player2,
        cell: 98,
        outcome: ShotOutcome.miss,
      ).toWire(),
      BattleshipShot(
        attacker: BattleshipSeat.player1,
        cell: 2,
        outcome: ShotOutcome.sunk,
        sunkShip: ShipType.cruiser,
        sunkCells: [0, 1, 2],
      ).toWire(),
    ];
    expect(() => BattleshipPlayerView.fromWire(wire), throwsFormatException);
  });

  test('finished snapshots preserve the turn at resignation and final hit', () {
    final resigned = readyGame();
    resigned.fire(BattleshipSeat.player1, 99);
    resigned.resign(BattleshipSeat.player1);
    final resignWire = copy(resigned.view(BattleshipSeat.player1).toWire());
    expect(
      BattleshipPlayerView.fromWire(resignWire).turn,
      BattleshipSeat.player2,
    );
    resignWire['turn'] = 0;
    expect(
      () => BattleshipPlayerView.fromWire(resignWire),
      throwsFormatException,
    );

    final won = readyGame();
    final targets = won
        .view(BattleshipSeat.player2)
        .ownFleet
        .expand((ship) => ship.cells)
        .toList();
    for (var index = 0; index < targets.length; index++) {
      won.fire(BattleshipSeat.player1, targets[index]);
      if (index < targets.length - 1) {
        won.fire(BattleshipSeat.player2, 50 + index);
      }
    }
    final winWire = copy(won.view(BattleshipSeat.player1).toWire());
    expect(BattleshipPlayerView.fromWire(winWire).turn, BattleshipSeat.player1);
    winWire['turn'] = 1;
    expect(() => BattleshipPlayerView.fromWire(winWire), throwsFormatException);
  });

  test(
    'wire collection limits reject oversized metadata before decoding it',
    () {
      final base = readyGame().view(BattleshipSeat.player1).toWire();
      for (final (key, length) in [
        ('ready', 3),
        ('ownFleet', 6),
        ('enemyFleet', 6),
        ('shots', 201),
      ]) {
        final wire = copy(base)..[key] = List<Object?>.filled(length, null);
        expect(
          () => BattleshipPlayerView.fromWire(wire),
          throwsFormatException,
          reason: '$key exceeds its maximum size',
        );
      }
      expect(
        () => BattleshipShot.fromWire({
          'attacker': 0,
          'cell': 0,
          'outcome': 'sunk',
          'sunkShip': 'carrier',
          'sunkCells': [0, 1, 2, 3, 4, 5],
        }),
        throwsFormatException,
      );
    },
  );
}
