import 'package:easyplay/board.dart';
import 'package:easyplay/game_page.dart';
import 'package:easyplay/game_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Go board fits the viewport after landscape and portrait resizes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
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
          const MaterialApp(
            home: GamePage(
              type: GameType.go,
              goConfig: GoConfig(boardSize: 19),
              askForSetup: false,
              allowComputerMoves: false,
              useAndroidKataGo: false,
            ),
          ),
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
    },
  );
}
