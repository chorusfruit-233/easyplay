import 'dart:async';

import 'package:easyplay/board.dart';
import 'package:easyplay/lan/lan_page.dart';
import 'package:easyplay/lan/lan_match_page.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_placement.dart';
import 'package:easyplay/lan/lan_game.dart';
import 'package:easyplay/lan/lan_transport.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_lan_connection.dart';

BoardPainter _boardPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(Board),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as BoardPainter;

Offset _point(WidgetTester tester, Cell cell) {
  final rect = tester.getRect(find.byType(Board));
  return rect.topLeft +
      Offset(
        (cell.col + .5) * rect.width / 9,
        (cell.row + .5) * rect.height / 9,
      );
}

void main() {
  for (final side in Side.values) {
    for (final mode in [
      GoPlacementMode.doubleTap,
      GoPlacementMode.swipeConfirm,
    ]) {
      testWidgets(
        'Go LAN ${side.name} preserves ${mode.name} confirmation and clears it on sync',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            GoPlacementPreferences.key: mode.name,
          });
          final connection = FakeLanConnection.go(side);
          await tester.pumpWidget(
            MaterialApp(home: LanMatchPage(connection: connection)),
          );
          await tester.pumpAndSettle();
          if (side == Side.white) {
            connection.commit(Side.black, LanMessageType.move, {
              'cell': [4, 3],
            });
            await tester.pumpAndSettle();
          }
          const first = Cell(4, 4), next = Cell(4, 6);
          Future<void> confirm(Cell cell) => mode == GoPlacementMode.doubleTap
              ? tester.tapAt(_point(tester, cell))
              : tester.dragFrom(_point(tester, cell), const Offset(0, 40));
          await tester.tapAt(_point(tester, first));
          await tester.pumpAndSettle();
          expect(_boardPainter(tester).preview, first);
          expect(connection.sent, isEmpty);
          await confirm(first);
          await tester.pumpAndSettle();
          expect(connection.sent.single.type, LanMessageType.move);
          expect(connection.replica!.session.pieceAt(first)?.side, side);

          connection.commit(side.opponent, LanMessageType.move, {
            'cell': [4, 5],
          });
          await tester.pumpAndSettle();
          await tester.tapAt(_point(tester, next));
          await tester.pumpAndSettle();
          expect(_boardPainter(tester).preview, next);
          final seq = connection.replica!.seq;
          connection.syncGo();
          await tester.pumpAndSettle();
          expect(connection.replica!.seq, seq);
          expect(_boardPainter(tester).preview, isNull);
          await tester.tapAt(_point(tester, next));
          await tester.pumpAndSettle();
          expect(connection.sent, hasLength(1));
          await confirm(next);
          await tester.pumpAndSettle();
          expect(connection.sent, hasLength(2));
          expect(connection.replica!.session.pieceAt(next)?.side, side);
          await tester.pumpWidget(const SizedBox());
          await connection.dispose();
        },
      );
    }
  }

  testWidgets('Go LAN disconnect cancels a held placement preview', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      GoPlacementPreferences.key: GoPlacementMode.pressRelease.name,
    });
    final connection = FakeLanConnection.go(Side.black);
    await tester.pumpWidget(
      MaterialApp(home: LanMatchPage(connection: connection)),
    );
    await tester.pumpAndSettle();
    const cell = Cell(4, 4);
    final gesture = await tester.startGesture(_point(tester, cell));
    await tester.pumpAndSettle();
    expect(_boardPainter(tester).preview, cell);
    connection.emitDisconnect();
    await tester.pumpAndSettle();
    expect(_boardPainter(tester).preview, isNull);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(connection.sent, isEmpty);
    expect(connection.replica!.session.moves, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });

  testWidgets(
    'Go LAN can unmark dead stones and clears marks when play resumes',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        GoPlacementPreferences.key: GoPlacementMode.direct.name,
      });
      final connection = FakeLanConnection.go(Side.black);
      connection.commit(Side.black, LanMessageType.move, {
        'cell': [4, 4],
      });
      connection.commit(Side.white, LanMessageType.pass);
      connection.commit(Side.black, LanMessageType.pass);
      await tester.pumpWidget(
        MaterialApp(home: LanMatchPage(connection: connection)),
      );
      await tester.pumpAndSettle();
      const cell = Cell(4, 4);
      await tester.tapAt(_point(tester, cell));
      await tester.pumpAndSettle();
      expect(_boardPainter(tester).deadStones, contains(cell));
      await tester.tapAt(_point(tester, cell));
      await tester.pumpAndSettle();
      expect(_boardPainter(tester).deadStones, isEmpty);
      await tester.tapAt(_point(tester, cell));
      await tester.pumpAndSettle();
      connection.commit(Side.black, LanMessageType.undoRequest);
      connection.commit(Side.white, LanMessageType.undoAccept, {
        'requestSeq': connection.replica!.seq,
      });
      await tester.pumpAndSettle();
      expect(connection.replica!.session.gameOver, isFalse);
      expect(_boardPainter(tester).deadStones, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await connection.dispose();
    },
  );

  testWidgets('LAN board fits below the status after viewport resizes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final connection = _FakeResignedConnection();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in const [
      Size(1280, 600),
      Size(900, 380),
      Size(700, 360),
      Size(390, 844),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(home: LanMatchPage(connection: connection)),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(Board));
      expect(rect.width, greaterThan(0));
      expect(rect.width, closeTo(rect.height, 0.01));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });

  testWidgets('guest waits for the host before opening the board', (
    tester,
  ) async {
    final connection = _FakeWaitingConnection();
    await tester.pumpWidget(
      MaterialApp(home: LanGuestWaitingPage(connection: connection)),
    );
    expect(find.text('已加入房间，等待房主开始对局'), findsOneWidget);
    expect(find.textContaining('你执白'), findsNothing);
    connection.start();
    await tester.pumpAndSettle();
    expect(find.textContaining('你执白'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });

  testWidgets('Go LAN resignation is shown as mid-game resignation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final connection = _FakeResignedConnection();
    await tester.pumpWidget(
      MaterialApp(home: LanMatchPage(connection: connection)),
    );
    await tester.pumpAndSettle();

    expect(find.text('终局：白方中盘认输'), findsOneWidget);
    expect(find.textContaining('胜 7.5 目'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });

  testWidgets('join page restores a recent address and validates the port', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'easyplay.lan.recent_addresses': ['192.168.1.23:8080'],
    });
    await tester.pumpWidget(const MaterialApp(home: LanJoinPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('192.168.1.23:8080'));
    await tester.pump();
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].controller!.text, '192.168.1.23');
    expect(fields[1].controller!.text, '8080');
    await tester.enterText(find.byType(TextField).at(1), '99999');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '99999',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '加入'))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('加入'));
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效端口'), findsOneWidget);
  });
}

class _FakeResignedConnection extends LanClientConnection {
  _FakeResignedConnection() : super(const GoConfig()) {
    replica = LanReplica(const GoConfig());
    side = Side.black;
    started = true;
    replica!.receive(LanMessage(LanMessageType.resign, 1, {'side': 'W'}));
  }

  final _events = StreamController<LanMessage>.broadcast();

  @override
  Stream<LanMessage> get messages => _events.stream;

  @override
  Future<void> close() async {}

  Future<void> dispose() => _events.close();
}

class _FakeWaitingConnection extends LanClientConnection {
  _FakeWaitingConnection() : super(const GoConfig()) {
    replica = LanReplica(const GoConfig());
    side = Side.white;
  }

  final _events = StreamController<LanMessage>.broadcast();
  @override
  Stream<LanMessage> get messages => _events.stream;

  void start() {
    started = true;
    _events.add(LanMessage(LanMessageType.matchStart, 0));
  }

  @override
  Future<void> close() async {}

  Future<void> dispose() => _events.close();
}
