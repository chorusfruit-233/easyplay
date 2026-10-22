import 'dart:math';

import 'package:easyplay/battleship/battleship_ai.dart';
import 'package:easyplay/battleship/battleship_model.dart';
import 'package:easyplay/battleship/battleship_session.dart';
import 'package:flutter_test/flutter_test.dart';

List<ShipPlacement> _ownFleet() => [
  ShipPlacement(ShipType.carrier, 0, ShipDirection.horizontal),
  ShipPlacement(ShipType.battleship, 10, ShipDirection.horizontal),
  ShipPlacement(ShipType.cruiser, 20, ShipDirection.horizontal),
  ShipPlacement(ShipType.submarine, 30, ShipDirection.horizontal),
  ShipPlacement(ShipType.destroyer, 40, ShipDirection.horizontal),
];

List<ShipPlacement> _enemyFleet({bool touching = false}) => [
  ShipPlacement(ShipType.carrier, touching ? 45 : 44, ShipDirection.horizontal),
  ShipPlacement(ShipType.battleship, 60, ShipDirection.horizontal),
  ShipPlacement(ShipType.cruiser, 70, ShipDirection.horizontal),
  ShipPlacement(ShipType.submarine, 80, ShipDirection.horizontal),
  ShipPlacement(
    ShipType.destroyer,
    touching ? 44 : 94,
    touching ? ShipDirection.vertical : ShipDirection.horizontal,
  ),
];

BattleshipSession _game({
  List<ShipPlacement>? enemy,
  List<ShipPlacement>? own,
}) {
  final session = BattleshipSession(random: Random(1));
  for (final placement in own ?? _ownFleet()) {
    session.place(BattleshipSeat.player1, placement);
  }
  for (final placement in enemy ?? _enemyFleet()) {
    session.place(BattleshipSeat.player2, placement);
  }
  session.ready(BattleshipSeat.player1);
  session.ready(BattleshipSeat.player2);
  return session;
}

/// Let player 2 miss before hitting any of player 1's ships, so long test
/// histories cannot accidentally finish the game on the opponent's turn.
void _shootAndReturn(BattleshipSession session, Iterable<int> targets) {
  final occupied = session
      .view(BattleshipSeat.player1)
      .ownFleet
      .expand((placement) => placement.cells)
      .toSet();
  final replies = [
    for (var cell = 0; cell < 100; cell++)
      if (!occupied.contains(cell)) cell,
    ...occupied,
  ];
  for (final cell in targets) {
    session.fire(BattleshipSeat.player1, cell);
    final count = session.view(BattleshipSeat.player2).outgoingShots.length;
    session.fire(BattleshipSeat.player2, replies[count]);
  }
}

void main() {
  test('only chooses during its own playing turn', () {
    final ai = BattleshipAi(random: Random(2));
    final placement = BattleshipSession();
    expect(
      () => ai.choose(placement.view(BattleshipSeat.player1)),
      throwsStateError,
    );
    final session = _game();
    expect(
      () => ai.choose(session.view(BattleshipSeat.player2)),
      throwsStateError,
    );
    session.resign(BattleshipSeat.player1);
    expect(
      () => ai.choose(session.view(BattleshipSeat.player1)),
      throwsStateError,
    );
  });

  test('publicly indistinguishable enemy fleets produce the same choices', () {
    final first = _game();
    final second = _game(
      enemy: [
        ShipPlacement(ShipType.carrier, 44, ShipDirection.horizontal),
        ShipPlacement(ShipType.battleship, 10, ShipDirection.horizontal),
        ShipPlacement(ShipType.cruiser, 20, ShipDirection.horizontal),
        ShipPlacement(ShipType.submarine, 30, ShipDirection.horizontal),
        ShipPlacement(ShipType.destroyer, 50, ShipDirection.horizontal),
      ],
    );
    _shootAndReturn(first, [44, 99]);
    _shootAndReturn(second, [44, 99]);
    final firstView = first.view(BattleshipSeat.player1);
    final secondView = second.view(BattleshipSeat.player1);
    expect(firstView.enemyFleet, isEmpty);
    expect(firstView.toWire(), secondView.toWire());
    final firstAi = BattleshipAi(random: Random(17));
    final secondAi = BattleshipAi(random: Random(17));
    expect(
      List.generate(20, (_) => firstAi.choose(firstView)),
      List.generate(20, (_) => secondAi.choose(secondView)),
    );
  });

  test('its own private fleet does not bias guesses about the enemy fleet', () {
    final first = _game();
    final second = _game(
      own: [
        ShipPlacement(ShipType.carrier, 5, ShipDirection.horizontal),
        ShipPlacement(ShipType.battleship, 15, ShipDirection.horizontal),
        ShipPlacement(ShipType.cruiser, 25, ShipDirection.horizontal),
        ShipPlacement(ShipType.submarine, 35, ShipDirection.horizontal),
        ShipPlacement(ShipType.destroyer, 45, ShipDirection.horizontal),
      ],
    );
    final firstAi = BattleshipAi(random: Random(23));
    final secondAi = BattleshipAi(random: Random(23));
    expect(
      List.generate(
        20,
        (_) => firstAi.choose(first.view(BattleshipSeat.player1)),
      ),
      List.generate(
        20,
        (_) => secondAi.choose(second.view(BattleshipSeat.player1)),
      ),
    );
  });

  test('pursues a hit and uses aligned hits to finish the damaged ship', () {
    final session = _game();
    _shootAndReturn(session, [44]);
    final first = BattleshipAi(
      random: Random(10),
    ).choose(session.view(BattleshipSeat.player1));
    expect([34, 43, 45, 54], contains(first));
    _shootAndReturn(session, [45]);
    final second = BattleshipAi(
      random: Random(10),
    ).choose(session.view(BattleshipSeat.player1));
    expect([43, 46], contains(second));
  });

  test('can finish a ship directly beside a sunken ship', () {
    final session = _game(enemy: _enemyFleet(touching: true));
    _shootAndReturn(session, [
      for (var cell = 0; cell < 100; cell++)
        if (cell != 45) cell,
    ]);
    final view = session.view(BattleshipSeat.player1);
    expect(view.phase, BattleshipPhase.playing);
    expect(
      view.outgoingShots
          .where((shot) => shot.outcome == ShotOutcome.sunk)
          .length,
      4,
    );
    final choice = BattleshipAi(random: Random(4)).choose(view);
    expect(choice, 45);
    session.fire(BattleshipSeat.player1, choice);
    expect(session.winner, BattleshipSeat.player1);
  });

  test('equally likely opening guesses vary without reading hidden state', () {
    final view = _game().view(BattleshipSeat.player1);
    final ai = BattleshipAi(random: Random(7));
    final choices = List.generate(40, (_) => ai.choose(view));
    expect(choices.toSet().length, greaterThan(1));
    expect(choices.every((cell) => cell >= 0 && cell < 100), isTrue);
  });

  test('seeded AI games always finish with legal, unrepeated guesses', () {
    for (var seed = 0; seed < 8; seed++) {
      final session = BattleshipSession(random: Random(seed));
      for (final seat in BattleshipSeat.values) {
        session.randomizeFleet(seat);
        session.ready(seat);
      }
      final players = [
        BattleshipAi(random: Random(seed * 2)),
        BattleshipAi(random: Random(seed * 2 + 1)),
      ];
      var shots = 0;
      while (session.phase == BattleshipPhase.playing) {
        final seat = session.turn;
        final view = session.view(seat);
        expect(view.enemyFleet, isEmpty);
        final choice = players[seat.index].choose(view);
        expect(view.canFire(choice), isTrue);
        session.fire(seat, choice);
        expect(++shots, lessThanOrEqualTo(199));
      }
      expect(session.winner, isNotNull);
      for (final seat in BattleshipSeat.values) {
        final fired = session
            .view(seat)
            .outgoingShots
            .map((shot) => shot.cell)
            .toList();
        expect(fired.toSet().length, fired.length);
      }
    }
  });
}
