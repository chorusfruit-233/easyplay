import 'dart:async';

import 'package:easyplay/lan/lan_page.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/lan/lan_game.dart';
import 'package:easyplay/lan/lan_transport.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
