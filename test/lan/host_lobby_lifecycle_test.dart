import 'dart:async';

import 'package:easyplay/game_session.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/gomoku/widgets/gomoku_lan_pages.dart';
import 'package:easyplay/lan/lan_match_page.dart';
import 'package:easyplay/lan/lan_page.dart';
import 'package:easyplay/lan/lan_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Lobby did not update');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

void main() {
  for (final gomoku in [false, true]) {
    testWidgets(
      '${gomoku ? 'Gomoku' : 'Go'} host returns and starts the room',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(800, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: gomoku ? const GomokuLanRoomPage() : const LanRoomPage(),
            ),
          );
        });
        await _pumpUntil(
          tester,
          () => find.textContaining('玩家 1/2').evaluate().isNotEmpty,
        );
        final pin = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data ?? '')
            .firstWhere((text) => text.startsWith('口令  '));
        final address = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data ?? '')
            .firstWhere((text) => text.startsWith('地址  '));
        final token = pin.substring('口令  '.length);
        final port = int.parse(address.split(':').last);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump(const Duration(minutes: 5));
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump();
        expect(find.textContaining('玩家 1/2'), findsOneWidget);
        expect(find.text(pin), findsOneWidget);
        expect(find.text(address), findsOneWidget);
        final start = find.widgetWithText(FilledButton, '开始对局');
        expect(tester.widget<FilledButton>(start).onPressed, isNull);
        final guest = gomoku
            ? LanClientConnection.gomoku()
            : LanClientConnection(const GoConfig());
        addTearDown(guest.close);
        await tester.runAsync(
          () => guest.connect(Uri.parse('ws://127.0.0.1:$port'), token: token),
        );
        await _pumpUntil(
          tester,
          () => find.textContaining('玩家 2/2').evaluate().isNotEmpty,
        );
        expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
        await tester.tap(start);
        await tester.pumpAndSettle();
        await _pumpUntil(tester, () => guest.started);
        expect(
          gomoku ? find.byType(GomokuBoard) : find.byType(LanMatchPage),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox());
          await guest.close();
        });
      },
    );
  }
}
