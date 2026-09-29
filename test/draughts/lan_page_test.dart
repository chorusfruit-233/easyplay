import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_lan_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final variant in DraughtsVariant.values) {
    testWidgets('join button follows address and token for ${variant.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: DraughtsLanJoinPage(variant: variant)),
      );
      final fields = find.byType(TextField);
      final join = find.widgetWithText(FilledButton, '加入');

      expect(tester.widget<FilledButton>(join).onPressed, isNull);
      await tester.enterText(fields.at(0), '192.168.1.23');
      await tester.pump();
      expect(tester.widget<FilledButton>(join).onPressed, isNull);
      await tester.enterText(fields.at(2), '1234');
      await tester.pump();
      expect(tester.widget<FilledButton>(join).onPressed, isNotNull);

      await tester.enterText(fields.at(2), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(join).onPressed, isNull);
      await tester.enterText(fields.at(2), '1234');
      await tester.enterText(fields.at(0), '');
      await tester.pump();
      expect(tester.widget<FilledButton>(join).onPressed, isNull);

      // Room selection fills the controller directly, without onChanged.
      tester.widget<TextField>(fields.at(0)).controller!.text = '192.168.1.24';
      await tester.pump();
      expect(tester.widget<FilledButton>(join).onPressed, isNotNull);

      // Exercise the enabled callback without opening a network connection.
      await tester.enterText(fields.at(1), '99999');
      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pump();
      expect(find.text('请输入有效端口'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
