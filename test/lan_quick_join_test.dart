import 'dart:convert';

import 'package:easyplay/draughts/draughts_variant.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_quick_join.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final game in ['go', 'chess', 'draughts']) {
    test('probe detects $game at the current dynamic port', () async {
      final origin = Uri.parse('http://192.168.1.20:8091/');
      final client = MockClient((request) async {
        expect(request.url, origin.resolve('/easyplay/probe'));
        return http.Response(
          jsonEncode({
            'app': 'easyplay',
            'version': lanProtocolVersion,
            'game': game,
            if (game == 'draughts') 'variant': 'international',
          }),
          200,
        );
      });
      final room = await LanWebRoom.probe(origin, client: client);
      expect(room!.game, game);
      expect(room.origin.port, 8091);
      if (game == 'draughts') {
        expect(room.variant, DraughtsVariant.international);
      }
      client.close();
    });
  }

  test('ordinary pages and unknown variants do not offer quick join', () async {
    for (final body in [
      '<html>ordinary site</html>',
      jsonEncode({'app': 'other', 'version': lanProtocolVersion, 'game': 'go'}),
      jsonEncode({
        'app': 'easyplay',
        'version': lanProtocolVersion,
        'game': 'draughts',
        'variant': 'unknown',
      }),
    ]) {
      final client = MockClient((_) async => http.Response(body, 200));
      expect(
        await LanWebRoom.probe(Uri.parse('http://host:8091'), client: client),
        isNull,
      );
      client.close();
    }
  });

  testWidgets('quick join asks only for a token and rejects empty input', (
    tester,
  ) async {
    final room = LanWebRoom(
      Uri.parse('http://192.168.1.20:8091'),
      'draughts',
      DraughtsVariant.english,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LanQuickJoinCard(loadRoom: () async => room)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('快捷加入'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('房间口令'), findsOneWidget);
    final join = find.widgetWithText(FilledButton, '加入');
    expect(tester.widget<FilledButton>(join).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(join).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.pump();
    expect(tester.widget<FilledButton>(join).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quick join remains hidden when no host is detected', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LanQuickJoinCard(loadRoom: () async => null)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('快捷加入'), findsNothing);
  });
}
