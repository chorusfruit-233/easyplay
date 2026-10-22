import 'dart:convert';
import 'dart:math';

import 'package:easyplay/battleship/battleship_model.dart';
import 'package:easyplay/battleship/battleship_session.dart';
import 'package:flutter_test/flutter_test.dart';

const p1 = BattleshipSeat.player1, p2 = BattleshipSeat.player2;

void arrange(BattleshipSession game, BattleshipSeat seat, {int offset = 0}) {
  for (final ship in ShipType.values) {
    game.place(
      seat,
      ShipPlacement(ship, offset + ship.index * 10, ShipDirection.horizontal),
    );
  }
}

BattleshipSession prepared() {
  final game = BattleshipSession(random: Random(1));
  arrange(game, p1);
  arrange(game, p2);
  game.ready(p1);
  game.ready(p2);
  return game;
}

void main() {
  test('classic fleet totals seventeen cells and touching ships are legal', () {
    final game = BattleshipSession();
    arrange(game, p1);
    final fleet = game.view(p1).ownFleet;
    expect(fleet.map((ship) => ship.ship.length), [5, 4, 3, 3, 2]);
    expect(fleet.expand((ship) => ship.cells).toSet(), hasLength(17));
    expect(fleet[0].cells, contains(0));
    expect(fleet[1].cells, contains(10));
    expect(game.view(p2).ownFleet, isEmpty);
    expect(game.view(p2).enemyFleet, isEmpty);
  });

  test('out-of-bounds and overlapping replacements are atomic', () {
    final game = BattleshipSession();
    arrange(game, p1);
    final old = jsonEncode(game.view(p1).toWire());
    final revision = game.revision;
    expect(
      () => game.place(
        p1,
        ShipPlacement(ShipType.carrier, 11, ShipDirection.horizontal),
      ),
      throwsArgumentError,
    );
    expect(
      () => ShipPlacement(ShipType.carrier, 8, ShipDirection.horizontal),
      throwsArgumentError,
    );
    expect(
      () => ShipPlacement(ShipType.carrier, 60, ShipDirection.vertical),
      throwsArgumentError,
    );
    expect(game.revision, revision);
    expect(jsonEncode(game.view(p1).toWire()), old);
    game.place(
      p1,
      ShipPlacement(ShipType.carrier, 50, ShipDirection.horizontal),
    );
    expect(
      game
          .view(p1)
          .ownFleet
          .singleWhere((ship) => ship.ship == ShipType.carrier)
          .start,
      50,
    );
    expect(game.view(p1).ownFleet, hasLength(5));
  });

  test('preview shares replacement rules and never mutates a fleet', () {
    final game = BattleshipSession();
    arrange(game, p1);
    final fleet = game.view(p1).ownFleet;
    expect(
      canPlaceBattleshipAt(
        fleet,
        ShipType.carrier,
        0,
        ShipDirection.horizontal,
      ),
      isTrue,
    );
    expect(
      canPlaceBattleshipAt(fleet, ShipType.carrier, 1, ShipDirection.vertical),
      isFalse,
    );
    expect(
      canPlaceBattleshipAt(
        fleet,
        ShipType.carrier,
        96,
        ShipDirection.horizontal,
      ),
      isFalse,
    );
    expect(
      canPlaceBattleshipAt(fleet, ShipType.carrier, -1, ShipDirection.vertical),
      isFalse,
    );
    expect(fleet.first.start, 0);
  });

  test(
    'ready requires the complete fleet, locks it and waits for the opponent',
    () {
      final game = BattleshipSession();
      expect(() => game.ready(p1), throwsArgumentError);
      arrange(game, p1);
      game.ready(p1);
      expect(game.phase, BattleshipPhase.placement);
      expect(game.view(p1).ownReady, isTrue);
      expect(game.view(p2).enemyReady, isTrue);
      final revision = game.revision;
      for (final action in <void Function()>[
        () => game.place(
          p1,
          ShipPlacement(ShipType.carrier, 90, ShipDirection.horizontal),
        ),
        () => game.remove(p1, ShipType.carrier),
        () => game.clearFleet(p1),
        () => game.randomizeFleet(p1),
        () => game.ready(p1),
        () => game.fire(p1, 0),
      ]) {
        expect(action, throwsStateError);
        expect(game.revision, revision);
      }
      arrange(game, p2);
      game.ready(p2);
      expect(game.phase, BattleshipPhase.playing);
      expect(game.turn, p1);
    },
  );

  test(
    'hit and miss both consume a turn; repeated or wrong-turn fire cannot mutate state',
    () {
      final game = prepared();
      expect(game.fire(p1, 0).outcome, ShotOutcome.hit);
      expect(game.turn, p2);
      expect(game.fire(p2, 99).outcome, ShotOutcome.miss);
      expect(game.turn, p1);
      final revision = game.revision;
      final wire = jsonEncode(game.view(p1).toWire());
      expect(() => game.fire(p1, 0), throwsStateError);
      expect(() => game.fire(p2, 50), throwsStateError);
      expect(() => game.fire(p1, -1), throwsArgumentError);
      expect(() => game.fire(p1, 100), throwsArgumentError);
      expect(game.revision, revision);
      expect(jsonEncode(game.view(p1).toWire()), wire);
      expect(game.view(p1).canFire(0), isFalse);
      expect(game.view(p1).canFire(1), isTrue);
      expect(game.view(p2).canFire(1), isFalse);
    },
  );

  test('only a completely hit ship reveals its identity and cells', () {
    final game = prepared();
    final old = game.view(p1);
    for (var cell = 0; cell < 5; cell++) {
      final shot = game.fire(p1, cell);
      expect(shot.outcome, cell == 4 ? ShotOutcome.sunk : ShotOutcome.hit);
      expect(shot.sunkShip, cell == 4 ? ShipType.carrier : null);
      expect(shot.sunkCells, cell == 4 ? [0, 1, 2, 3, 4] : isEmpty);
      if (cell < 4) game.fire(p2, 90 + cell);
    }
    expect(game.view(p1).enemyFleet, isEmpty);
    expect(game.view(p2).enemyFleet, isEmpty);
    expect(old.shots, isEmpty);
    expect(old.ownFleet, hasLength(5));
    expect(game.view(p1).outgoingShots, hasLength(5));
    expect(game.view(p1).incomingShots, hasLength(4));
  });

  test(
    'all seventeen hits end play immediately, reveal fleets, and reset rotates first player',
    () {
      final game = prepared();
      final targets = game
          .view(p2)
          .ownFleet
          .expand((ship) => ship.cells)
          .toList();
      for (var i = 0; i < targets.length; i++) {
        game.fire(p1, targets[i]);
        if (i < targets.length - 1) game.fire(p2, 50 + i);
      }
      expect(game.phase, BattleshipPhase.finished);
      expect(game.winner, p1);
      for (final seat in BattleshipSeat.values) {
        final view = game.view(seat);
        expect(view.enemyFleet, hasLength(5));
        expect(view.isTurn, isFalse);
        expect(
          BattleshipPlayerView.fromWire(view.toWire()).toWire(),
          view.toWire(),
        );
      }
      final revision = game.revision;
      expect(() => game.fire(p2, 99), throwsStateError);
      expect(() => game.resign(p1), throwsStateError);
      expect(game.revision, revision);
      game.reset();
      expect(game.turn, p2);
      expect(game.phase, BattleshipPhase.placement);
      expect(game.winner, isNull);
      for (final seat in BattleshipSeat.values) {
        expect(game.view(seat).ownFleet, isEmpty);
        expect(game.view(seat).enemyFleet, isEmpty);
        expect(game.view(seat).shots, isEmpty);
        expect(game.view(seat).ready, [false, false]);
      }
      game.reset();
      expect(game.turn, p1);
    },
  );

  test(
    'either player can resign after battle starts and explicit first override is respected',
    () {
      final game = prepared();
      game.resign(p2);
      expect(game.winner, p1);
      expect(game.phase, BattleshipPhase.finished);
      expect(game.view(p1).enemyFleet, hasLength(5));
      game.reset(first: p2);
      expect(game.turn, p2);
      expect(() => game.resign(p1), throwsStateError);
    },
  );

  test('random fleets stay legal across seeds, both seats and rotations', () {
    for (var seed = 0; seed < 100; seed++) {
      final game = BattleshipSession(random: Random(seed));
      for (final seat in BattleshipSeat.values) {
        game.randomizeFleet(seat);
        final fleet = game.view(seat).ownFleet;
        validateBattleshipFleet(fleet, complete: true);
        expect(fleet.expand((ship) => ship.cells).toSet(), hasLength(17));
        expect(game.view(seat.opponent).enemyFleet, isEmpty);
        game.ready(seat);
      }
      expect(game.phase, BattleshipPhase.playing);
      game.fire(game.turn, seed % 100);
      for (final seat in BattleshipSeat.values) {
        final view = game.view(seat);
        expect(
          BattleshipPlayerView.fromWire(view.toWire()).toWire(),
          view.toWire(),
        );
      }
    }
  });

  test(
    'the longest legal battle ends on shot 199 with bounded public history',
    () {
      final game = BattleshipSession();
      for (final seat in BattleshipSeat.values) {
        arrange(game, seat);
        game.place(
          seat,
          ShipPlacement(ShipType.destroyer, 98, ShipDirection.horizontal),
        );
        game.ready(seat);
      }
      for (var cell = 0; cell < 99; cell++) {
        game.fire(p1, cell);
        game.fire(p2, cell);
      }
      expect(game.phase, BattleshipPhase.playing);
      for (final seat in BattleshipSeat.values) {
        final view = game.view(seat);
        expect(view.shots, hasLength(198));
        expect(view.enemyFleet, isEmpty);
        expect(
          BattleshipPlayerView.fromWire(view.toWire()).toWire(),
          view.toWire(),
        );
      }
      expect(game.fire(p1, 99).outcome, ShotOutcome.sunk);
      expect(game.winner, p1);
      for (final seat in BattleshipSeat.values) {
        final view = game.view(seat);
        expect(view.shots, hasLength(199));
        expect(view.enemyFleet, hasLength(5));
        expect(
          BattleshipPlayerView.fromWire(view.toWire()).toWire(),
          view.toWire(),
        );
      }
    },
  );
}
