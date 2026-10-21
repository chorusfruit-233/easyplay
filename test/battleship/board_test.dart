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
    expect(find.bySemanticsLabel('敌方海域 B4 未侦察'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
