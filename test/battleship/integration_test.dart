import 'dart:convert';

import 'package:easyplay/battleship/widgets/battleship_home_page.dart';
import 'package:easyplay/battleship/widgets/battleship_lobby_page.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_quick_join.dart';
import 'package:easyplay/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('seventh home entry opens the dedicated Battleship section', (
    tester,
  ) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.pumpAndSettle();
    expect(find.text('7 款'), findsOneWidget);
    await tester.ensureVisible(find.text('海战棋'));
    await tester.tap(find.text('海战棋'));
    await tester.pumpAndSettle();
    expect(find.byType(BattleshipHomePage), findsOneWidget);
    expect(find.byType(GamePage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('Battleship cannot fall through to the public Go session', () {
    expect(() => GameSession(GameType.battleship), throwsUnsupportedError);
  });

  final probe = <String, Object?>{
    'app': 'easyplay',
    'version': lanProtocolVersion,
    'game': 'battleship',
    'protocolVersion': 1,
    'rulesVersion': 1,
    'players': 1,
    'maxPlayers': 2,
  };
  test('Battleship probe keeps the secure origin and dynamic port', () async {
    final origin = Uri.parse('https://room.example:8091/');
    final client = MockClient((request) async {
      expect(request.url, origin.resolve('/easyplay/probe'));
      return http.Response(jsonEncode(probe), 200);
    });
    addTearDown(client.close);
    final room = await LanWebRoom.probe(origin, client: client);
    expect(room, isNotNull);
    expect(room!.label, '海战棋');
    expect(room.game, 'battleship');
    expect(room.origin, origin);
  });

  for (final field in [
    'version',
    'protocolVersion',
    'rulesVersion',
    'maxPlayers',
  ]) {
    test('Battleship probe rejects incompatible $field', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({...probe, field: 99}), 200),
      );
      addTearDown(client.close);
      expect(
        await LanWebRoom.probe(
          Uri.parse('http://192.168.1.20:8091'),
          client: client,
        ),
        isNull,
      );
    });
  }

  for (final direct in [false, true]) {
    testWidgets(
      'Battleship quick join uses its private-state lobby ($direct)',
      (tester) async {
        final origin = Uri.parse('https://room.example:8091');
        final room = LanWebRoom(origin, 'battleship', null);
        await tester.pumpWidget(
          MaterialApp(
            home: direct
                ? LanQuickJoinPage(room: room)
                : Scaffold(body: LanQuickJoinCard(loadRoom: () async => room)),
          ),
        );
        await tester.pumpAndSettle();
        if (!direct) {
          await tester.tap(find.text('快捷加入'));
          await tester.pumpAndSettle();
        }
        final lobby = tester.widget<BattleshipLobbyPage>(
          find.byType(BattleshipLobbyPage),
        );
        expect(lobby.initialOrigin, origin);
        expect(find.byType(TextField), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
