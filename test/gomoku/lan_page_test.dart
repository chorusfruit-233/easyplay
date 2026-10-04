import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_variant.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/gomoku/widgets/gomoku_lan_pages.dart';
import 'package:easyplay/go_placement.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_lan_connection.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      GoPlacementPreferences.key: GoPlacementMode.doubleTap.name,
    });
  });

  testWidgets('join still requires address, valid port and room token', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GomokuLanJoinPage()));
    final fields = find.byType(TextField);
    final join = find.widgetWithText(FilledButton, '加入');
    expect(tester.widget<FilledButton>(join).onPressed, isNull);
    await tester.enterText(fields.at(0), '192.168.1.23');
    await tester.pump();
    expect(tester.widget<FilledButton>(join).onPressed, isNull);
    await tester.enterText(fields.at(2), '1234');
    await tester.pump();
    expect(tester.widget<FilledButton>(join).onPressed, isNotNull);
    await tester.enterText(fields.at(1), '99999');
    await tester.ensureVisible(join);
    await tester.tap(join);
    await tester.pump();
    expect(find.text('请输入有效端口'), findsOneWidget);
  });

  testWidgets('guest waits for host and cannot place a stone', (tester) async {
    final connection = FakeLanConnection.gomoku(Side.white)..started = false;
    await tester.pumpWidget(
      MaterialApp(home: GomokuLanWaitingPage(connection: connection)),
    );
    await tester.pumpAndSettle();
    expect(find.text('已加入五子棋房间，等待房主开始'), findsOneWidget);
    expect(find.byType(GomokuBoard), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });

  testWidgets('LAN obeys placement confirmation and authenticated turn', (
    tester,
  ) async {
    final connection = FakeLanConnection.gomoku(Side.black);
    await tester.pumpWidget(
      MaterialApp(home: GomokuLanMatchPage(connection: connection)),
    );
    await tester.pumpAndSettle();
    final board = find.byType(GomokuBoard);
    final centre = tester.getCenter(board);
    await tester.tapAt(centre);
    await tester.pump();
    expect(connection.sent, isEmpty);
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(connection.sent.single.type, LanMessageType.move);
    expect(
      connection.gomokuReplica!.session.pieceAt(const Cell(7, 7)),
      Side.black,
    );
    expect(find.text('轮到对手 · 白方'), findsOneWidget);
    await tester.tapAt(centre + const Offset(25, 0));
    await tester.tapAt(centre + const Offset(25, 0));
    await tester.pumpAndSettle();
    expect(connection.sent, hasLength(1));

    final undo = find.text('请求悔棋');
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(connection.sent.last.type, LanMessageType.undoRequest);
    expect(find.text('等待处理悔棋请求…'), findsOneWidget);
    connection.commit(Side.white, LanMessageType.undoAccept, {
      'requestSeq': connection.seq,
    });
    await tester.pumpAndSettle();
    expect(connection.gomokuReplica!.session.moves, isEmpty);
    expect(find.text('轮到你 · 黑方'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });

  testWidgets('LAN board fits a short landscape viewport', (tester) async {
    tester.view.physicalSize = const Size(850, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connection = FakeLanConnection.gomoku(Side.black);
    await tester.pumpWidget(
      MaterialApp(home: GomokuLanMatchPage(connection: connection)),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(GomokuBoard));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(360));
    expect(rect.width, closeTo(rect.height, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });

  testWidgets('Renju LAN shows its rule and explains a forbidden point', (
    tester,
  ) async {
    final connection = FakeLanConnection.gomoku(
      Side.black,
      variant: GomokuVariant.renju,
    );
    const black = [Cell(7, 6), Cell(7, 8), Cell(6, 7), Cell(8, 7)];
    const white = [Cell(0, 0), Cell(0, 2), Cell(2, 0), Cell(2, 2)];
    for (var i = 0; i < black.length; i++) {
      connection.commit(Side.black, LanMessageType.move, {
        'cell': [black[i].row, black[i].col],
      });
      connection.commit(Side.white, LanMessageType.move, {
        'cell': [white[i].row, white[i].col],
      });
    }
    await tester.pumpWidget(
      MaterialApp(home: GomokuLanMatchPage(connection: connection)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('连珠禁手'), findsOneWidget);
    final centre = tester.getCenter(find.byType(GomokuBoard));
    await tester.tapAt(centre);
    await tester.pump();
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(find.text('双活三禁手'), findsOneWidget);
    expect(connection.sent, isEmpty);
    expect(connection.seq, 8);
    expect(connection.gomokuReplica!.session.pieceAt(const Cell(7, 7)), isNull);
    expect(find.text('轮到你 · 黑方'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });
}
