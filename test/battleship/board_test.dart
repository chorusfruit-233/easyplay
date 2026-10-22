import 'package:easyplay/battleship/widgets/battleship_board.dart';
import 'package:easyplay/battleship/battleship_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('coordinate taps and disabled cells stay correct under RTL', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
              child: BattleshipBoard(
                id: 'target',
                label: '敌方海域',
                onCell: selected.add,
                canSelect: (cell) => cell != 0,
              ),
            ),
          ),
        ),
      ),
    );
    final a1 = find.byKey(const ValueKey('battleship-target-cell-0'));
    final a10 = find.byKey(const ValueKey('battleship-target-cell-9'));
    final j1 = find.byKey(const ValueKey('battleship-target-cell-90'));
    expect(tester.getCenter(a1).dx, lessThan(tester.getCenter(a10).dx));
    expect(tester.getCenter(a1).dy, lessThan(tester.getCenter(j1).dy));
    await tester.tap(a1);
    expect(selected, isEmpty);
    await tester.tap(find.bySemanticsLabel('敌方海域 C4 未侦察'));
    expect(selected, [23]);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('keyboard activation chooses an unfired coordinate', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BattleshipBoard(
            id: 'target',
            label: '敌方海域',
            onCell: selected.add,
            canSelect: (cell) => cell == 42,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, [42]);
    final board = find.byKey(const ValueKey('battleship-target-board'));
    expect(tester.getSize(board).width, lessThanOrEqualTo(480));
    expect(tester.getSize(board).aspectRatio, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sinking marks the whole public ship with accessible status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BattleshipBoard(
            id: 'target',
            label: '敌方海域',
            shots: [
              BattleshipShot(
                attacker: BattleshipSeat.player1,
                cell: 0,
                outcome: ShotOutcome.miss,
              ),
              BattleshipShot(
                attacker: BattleshipSeat.player1,
                cell: 2,
                outcome: ShotOutcome.hit,
              ),
              BattleshipShot(
                attacker: BattleshipSeat.player1,
                cell: 12,
                outcome: ShotOutcome.sunk,
                sunkShip: ShipType.destroyer,
                sunkCells: [2, 12],
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('敌方海域 A1 未命中'), findsOneWidget);
    expect(find.bySemanticsLabel('敌方海域 A3 已击沉驱逐舰'), findsOneWidget);
    expect(find.bySemanticsLabel('敌方海域 B3 已击沉驱逐舰'), findsOneWidget);
    expect(find.bySemanticsLabel('敌方海域 B4 已排除，击沉周边'), findsOneWidget);
    expect(find.bySemanticsLabel('敌方海域 B5 未侦察'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('public surrounding water is excluded without recording a shot', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final selected = <int>[];
    final shots = [
      BattleshipShot(
        attacker: BattleshipSeat.player1,
        cell: 18,
        outcome: ShotOutcome.miss,
      ),
      BattleshipShot(
        attacker: BattleshipSeat.player1,
        cell: 8,
        outcome: ShotOutcome.hit,
      ),
      BattleshipShot(
        attacker: BattleshipSeat.player1,
        cell: 9,
        outcome: ShotOutcome.sunk,
        sunkShip: ShipType.destroyer,
        sunkCells: [8, 9],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BattleshipBoard(
            id: 'target',
            label: '敌方海域',
            shots: shots,
            onCell: selected.add,
            // The board also protects public unavailable cells when a caller
            // supplies no additional turn or placement predicate.
          ),
        ),
      ),
    );
    for (final cell in [7, 8, 9, 17, 18, 19]) {
      final tile = find.byKey(ValueKey('battleship-target-cell-$cell'));
      await tester.tap(tile);
      expect(
        tester.widget<Semantics>(tile).properties.onTap,
        isNull,
        reason: 'A public shot or inferred water cannot be activated',
      );
    }
    expect(selected, isEmpty);
    expect(find.bySemanticsLabel('敌方海域 B9 未命中'), findsOneWidget);
    expect(find.bySemanticsLabel('敌方海域 B10 已排除，击沉周边'), findsOneWidget);
    expect(find.bySemanticsLabel('敌方海域 A1 未侦察'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('敌方海域 B7 未侦察'));
    expect(selected, [16]);
    expect(shots.length, 3);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BattleshipBoard(id: 'own', label: '我方海域', shots: shots),
        ),
      ),
    );
    expect(find.bySemanticsLabel('我方海域 B10 已排除，击沉周边'), findsOneWidget);
    expect(find.bySemanticsLabel('我方海域 B9 未命中'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'keyboard focus skips inferred water without a caller predicate',
    (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BattleshipBoard(
              id: 'target',
              label: '敌方海域',
              shots: [
                BattleshipShot(
                  attacker: BattleshipSeat.player1,
                  cell: 0,
                  outcome: ShotOutcome.hit,
                ),
                BattleshipShot(
                  attacker: BattleshipSeat.player1,
                  cell: 1,
                  outcome: ShotOutcome.sunk,
                  sunkShip: ShipType.destroyer,
                  sunkCells: [0, 1],
                ),
              ],
              onCell: selected.add,
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, [3]);
    },
  );

  testWidgets('small themed boards preserve both ship orientations and marks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: brightness,
            ),
          ),
          home: Scaffold(
            body: BattleshipBoard(
              id: 'own',
              label: '我方海域',
              fleet: [
                ShipPlacement(ShipType.carrier, 0, ShipDirection.horizontal),
                ShipPlacement(ShipType.battleship, 9, ShipDirection.vertical),
                ShipPlacement(ShipType.cruiser, 20, ShipDirection.horizontal),
                ShipPlacement(ShipType.submarine, 55, ShipDirection.vertical),
                ShipPlacement(ShipType.destroyer, 90, ShipDirection.horizontal),
              ],
              shots: [
                for (final cell in [21, 55, 65])
                  BattleshipShot(
                    attacker: BattleshipSeat.player2,
                    cell: cell,
                    outcome: ShotOutcome.hit,
                  ),
                BattleshipShot(
                  attacker: BattleshipSeat.player2,
                  cell: 44,
                  outcome: ShotOutcome.miss,
                ),
                BattleshipShot(
                  attacker: BattleshipSeat.player2,
                  cell: 75,
                  outcome: ShotOutcome.sunk,
                  sunkShip: ShipType.submarine,
                  sunkCells: [55, 65, 75],
                ),
              ],
              selected: 37,
              preview: const [37, 38],
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('我方海域 A5 航母'), findsOneWidget);
      expect(find.bySemanticsLabel('我方海域 D10 战列舰'), findsOneWidget);
      expect(find.bySemanticsLabel('我方海域 C2 命中'), findsOneWidget);
      expect(find.bySemanticsLabel('我方海域 H6 已击沉潜艇'), findsOneWidget);
      expect(find.bySemanticsLabel('我方海域 E5 未命中'), findsOneWidget);
      expect(find.bySemanticsLabel('我方海域 D8 布阵预览'), findsOneWidget);
      expect(find.bySemanticsLabel('我方海域 J2 驱逐舰'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });
}
