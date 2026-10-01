import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/lan/rtc_lobby_page.dart';
import 'package:easyplay/lan/rtc_transport.dart';

void main() {
  testWidgets('unsupported platform hides browser-only RTC entry', (
    tester,
  ) async {
    expect(rtcSupported, isFalse);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RtcLobbyEntry(game: 'go')),
      ),
    );
    expect(find.text('浏览器点对点联机'), findsNothing);
  });
  testWidgets('STUN options default to domestic and support custom servers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RtcLobbyPage(game: 'chess')),
    );
    await tester.tap(find.text('连接选项'));
    await tester.pumpAndSettle();
    expect(find.text('国内服务（小米、芒果）'), findsOneWidget);
    expect(find.textContaining('stun:stun.miwifi.com:3478'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义服务').last);
    await tester.pumpAndSettle();
    expect(find.text('STUN 地址（每行一个，最多 4 个）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('manual signaling rejects bad input and offers cancellation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RtcLobbyPage(game: 'chess')),
    );
    await tester.enterText(find.byType(TextField), '{bad invitation');
    await tester.tap(find.text('导入'));
    await tester.pump();
    expect(find.textContaining('FormatException'), findsOneWidget);
    await tester.ensureVisible(find.text('取消 / 重试'));
    await tester.tap(find.text('取消 / 重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('FormatException'), findsNothing);
    expect(find.text('已取消，可重新创建或加入'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
