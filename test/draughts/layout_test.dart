import 'dart:async';

import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_board.dart';
import 'package:easyplay/draughts/widgets/draughts_game_page.dart';
import 'package:easyplay/draughts/widgets/draughts_lan_pages.dart';
import 'package:easyplay/game_session.dart' show Side;
import 'package:easyplay/lan/draughts_lan_game.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final online in [false, true]) {
    for (final variant in [
      DraughtsVariant.english,
      DraughtsVariant.international,
    ]) {
      testWidgets(
        '${variant.name} ${online ? 'LAN' : 'local'} board fits without scrolling',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final connection = _Connection(variant);
          final page = online
              ? DraughtsLanMatchPage(connection: connection, variant: variant)
              : DraughtsGamePage(
                  session: DraughtsSession(DraughtsRules.forVariant(variant)),
                );
          for (final size in const [
            Size(1432, 772), // Screenshot viewport at DPR 2.
            Size(900, 380),
            Size(700, 360),
            Size(390, 844),
          ]) {
            tester.view.physicalSize = size;
            await tester.pumpWidget(MaterialApp(home: page));
            await tester.pumpAndSettle();
            final rect = tester.getRect(find.byType(DraughtsBoard));
            expect(rect.width, greaterThan(0));
            expect(rect.width, closeTo(rect.height, .01));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          await connection.dispose();
        },
      );
    }
  }
}

class _Connection extends LanClientConnection {
  _Connection(DraughtsVariant variant) : super.draughts(variant) {
    draughtsReplica = DraughtsLanReplica(variant);
    side = Side.white;
    started = true;
  }

  final _events = StreamController<LanMessage>.broadcast();
  @override
  Stream<LanMessage> get messages => _events.stream;
  @override
  Future<void> close() async {}
  Future<void> dispose() => _events.close();
}
