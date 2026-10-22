import 'package:easyplay/battleship/battleship.dart';
import 'package:easyplay/battleship/battleship_match_controller.dart';
import 'package:flutter_test/flutter_test.dart';

List<ShipPlacement> _fleet({int rowOffset = 0}) => [
  for (final ship in ShipType.values)
    ShipPlacement(
      ship,
      (ship.index + rowOffset) * battleshipBoardSize,
      ShipDirection.horizontal,
    ),
];

void _placeFleet(BattleshipMatchController controller, {int rowOffset = 0}) {
  for (final placement in _fleet(rowOffset: rowOffset)) {
    controller.place(placement);
  }
}

void _startHotseat(BattleshipMatchController controller) {
  controller.reveal();
  _placeFleet(controller);
  controller.ready();
  controller.reveal();
  _placeFleet(controller, rowOffset: 5);
  controller.ready();
  controller.reveal();
}

void main() {
  test('hotseat covers both fleets until the receiving player confirms', () {
    final controller = BattleshipMatchController.hotseat();
    addTearDown(controller.dispose);

    expect(controller.covered, isTrue);
    expect(controller.view, isNull);
    expect(controller.handoffSeat, BattleshipSeat.player1);
    expect(controller.canAct, isFalse);
    expect(controller.randomize, throwsStateError);

    controller.reveal();
    _placeFleet(controller);
    expect(controller.view!.ownFleet, _fleet());
    expect(controller.view!.enemyFleet, isEmpty);
    controller.ready();

    expect(controller.covered, isTrue);
    expect(controller.view, isNull);
    expect(controller.handoffSeat, BattleshipSeat.player2);
    expect(controller.revision, greaterThan(0));
    expect(controller.ready, throwsStateError);

    controller.reveal();
    expect(controller.view!.seat, BattleshipSeat.player2);
    expect(controller.view!.ownFleet, isEmpty);
    expect(controller.view!.enemyReady, isTrue);
    expect(controller.view!.enemyFleet, isEmpty);
    _placeFleet(controller, rowOffset: 5);
    controller.ready();

    expect(controller.covered, isTrue);
    expect(controller.view, isNull);
    expect(controller.handoffSeat, BattleshipSeat.player1);
    controller.reveal();
    expect(controller.view!.phase, BattleshipPhase.playing);
    expect(controller.view!.ownFleet, _fleet());
    expect(controller.view!.enemyFleet, isEmpty);
  });

  test(
    'manual placement can rotate, remove, randomize and clear the fleet',
    () {
      final controller = BattleshipMatchController.hotseat();
      addTearDown(controller.dispose);
      controller.reveal();

      final horizontal = ShipPlacement(
        ShipType.carrier,
        0,
        ShipDirection.horizontal,
      );
      final vertical = ShipPlacement(
        ShipType.carrier,
        0,
        ShipDirection.vertical,
      );
      controller.place(horizontal);
      controller.place(vertical);
      expect(controller.view!.ownFleet, [vertical]);

      final revision = controller.revision;
      expect(
        () => controller.place(
          ShipPlacement(ShipType.destroyer, 10, ShipDirection.horizontal),
        ),
        throwsArgumentError,
      );
      expect(controller.revision, revision);
      expect(controller.view!.ownFleet, [vertical]);

      controller.remove(ShipType.carrier);
      expect(controller.view!.ownFleet, isEmpty);
      controller.randomize();
      final fleet = controller.view!.ownFleet;
      expect(fleet.map((ship) => ship.ship).toSet(), ShipType.values.toSet());
      expect(fleet.expand((ship) => ship.cells).toSet(), hasLength(17));
      controller.clear();
      expect(controller.view!.ownFleet, isEmpty);
      expect(controller.ready, throwsArgumentError);
    },
  );

  test('pausing hotseat hides private fleets until an active reveal', () {
    final controller = BattleshipMatchController.hotseat();
    addTearDown(controller.dispose);
    controller.reveal();
    _placeFleet(controller);

    controller.setActive(false);
    expect(controller.covered, isTrue);
    expect(controller.view, isNull);
    expect(controller.canAct, isFalse);
    controller.reveal();
    expect(controller.view, isNull);
    expect(controller.clear, throwsStateError);

    controller.setActive(true);
    expect(controller.view, isNull);
    expect(controller.handoffSeat, BattleshipSeat.player1);
    controller.reveal();
    expect(controller.view!.ownFleet, _fleet());

    controller.ready();
    controller.reveal();
    _placeFleet(controller, rowOffset: 5);
    controller.ready();
    controller.reveal();
    controller.setActive(false);
    controller.setActive(true);
    expect(controller.view, isNull);
    expect(controller.handoffSeat, BattleshipSeat.player1);
    controller.reveal();
    expect(controller.view!.phase, BattleshipPhase.playing);
    expect(controller.view!.ownFleet, _fleet());
    expect(controller.view!.enemyFleet, isEmpty);
  });

  test('every shot hands off privately, including hits and sunk ships', () {
    final controller = BattleshipMatchController.hotseat();
    addTearDown(controller.dispose);
    _startHotseat(controller);

    controller.fire(50);
    expect(controller.shots.single.outcome, ShotOutcome.hit);
    expect(controller.covered, isTrue);
    expect(controller.view, isNull);
    expect(controller.handoffSeat, BattleshipSeat.player2);
    expect(() => controller.fire(51), throwsStateError);

    controller.reveal();
    expect(controller.view!.incomingShots.single.cell, 50);
    expect(controller.view!.ownFleet, _fleet(rowOffset: 5));
    expect(controller.view!.enemyFleet, isEmpty);
    controller.fire(99);
    expect(controller.shots.last.outcome, ShotOutcome.miss);
    expect(controller.handoffSeat, BattleshipSeat.player1);
    expect(controller.view, isNull);

    controller.reveal();
    final revision = controller.revision;
    expect(() => controller.fire(50), throwsStateError);
    expect(controller.revision, revision);
    expect(controller.covered, isFalse);
    expect(controller.view!.shots, hasLength(2));

    for (final cell in [51, 52, 53, 54]) {
      controller.fire(cell);
      if (cell == 54) {
        expect(controller.shots.last.outcome, ShotOutcome.sunk);
        expect(controller.shots.last.sunkShip, ShipType.carrier);
        expect(controller.shots.last.sunkCells, [50, 51, 52, 53, 54]);
      }
      expect(controller.covered, isTrue);
      controller.reveal();
      controller.fire(98 - (cell - 51));
      controller.reveal();
    }
    expect(controller.view!.enemyFleet, isEmpty);
  });

  test('winning reveals the result and rematch rotates the starting seat', () {
    final controller = BattleshipMatchController.hotseat();
    addTearDown(controller.dispose);
    _startHotseat(controller);
    final targets = _fleet(rowOffset: 5).expand((ship) => ship.cells).toList();
    for (var i = 0; i < targets.length; i++) {
      controller.fire(targets[i]);
      if (i < targets.length - 1) {
        expect(controller.view, isNull);
        controller.reveal();
        controller.fire(99 - i);
        controller.reveal();
      }
    }

    expect(controller.covered, isFalse);
    expect(controller.view!.phase, BattleshipPhase.finished);
    expect(controller.view!.winner, BattleshipSeat.player1);
    expect(controller.view!.enemyFleet, _fleet(rowOffset: 5));
    expect(controller.view!.outgoingShots, hasLength(17));

    controller.rematch();
    expect(controller.view, isNull);
    expect(controller.covered, isTrue);
    controller.reveal();
    expect(controller.view!.phase, BattleshipPhase.placement);
    expect(controller.view!.turn, BattleshipSeat.player2);
    expect(controller.view!.ownFleet, isEmpty);
    expect(controller.view!.enemyFleet, isEmpty);
    expect(controller.view!.ready, [false, false]);
    expect(controller.view!.shots, isEmpty);

    _placeFleet(controller);
    controller.ready();
    controller.reveal();
    _placeFleet(controller, rowOffset: 5);
    controller.ready();
    expect(controller.handoffSeat, BattleshipSeat.player2);
  });

  test('resign ends the match and an unfinished match cannot rematch', () {
    final controller = BattleshipMatchController.hotseat();
    addTearDown(controller.dispose);
    expect(controller.rematch, throwsStateError);
    _startHotseat(controller);
    expect(controller.rematch, throwsStateError);
    controller.resign();
    expect(controller.view!.phase, BattleshipPhase.finished);
    expect(controller.view!.winner, BattleshipSeat.player2);
    expect(controller.view!.enemyFleet, _fleet(rowOffset: 5));
  });

  testWidgets('single player pauses and resumes exactly one pending AI turn', (
    tester,
  ) async {
    final controller = BattleshipMatchController.singlePlayer(
      aiDelay: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    expect(controller.view!.enemyReady, isTrue);
    expect(controller.view!.enemyFleet, isEmpty);
    _placeFleet(controller);
    controller.ready();
    controller.fire(99);
    expect(controller.thinking, isTrue);
    expect(controller.canAct, isFalse);
    await tester.pump(const Duration(milliseconds: 500));

    controller.setActive(false);
    final revision = controller.revision;
    await tester.pump(const Duration(seconds: 5));
    expect(controller.view!.shots, hasLength(1));
    expect(controller.revision, revision);
    expect(controller.canAct, isFalse);

    controller.setActive(true);
    await tester.pump(const Duration(milliseconds: 999));
    expect(controller.view!.shots, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.view!.shots, hasLength(2));
    expect(controller.view!.shots.last.attacker, BattleshipSeat.player2);
    expect(controller.thinking, isFalse);
    expect(controller.canAct, isTrue);
    expect(controller.view!.enemyFleet, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    expect(controller.view!.shots, hasLength(2));
  });

  testWidgets(
    'AI starts when human is player two and dispose cancels its turn',
    (tester) async {
      final controller = BattleshipMatchController.singlePlayer(
        human: BattleshipSeat.player2,
        aiDelay: const Duration(seconds: 1),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      _placeFleet(controller);
      controller.ready();
      expect(controller.view!.seat, BattleshipSeat.player2);
      expect(controller.thinking, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.view!.shots.single.attacker, BattleshipSeat.player1);
      expect(controller.thinking, isFalse);

      controller.fire(99);
      expect(controller.thinking, isTrue);
      final revision = controller.revision;
      final notificationsBeforeDispose = notifications;
      controller.dispose();
      await tester.pump(const Duration(seconds: 5));
      expect(controller.revision, revision);
      expect(notifications, notificationsBeforeDispose);
      expect(controller.view!.shots, hasLength(2));
      expect(controller.randomize, throwsStateError);
      expect(tester.takeException(), isNull);
    },
  );
}
