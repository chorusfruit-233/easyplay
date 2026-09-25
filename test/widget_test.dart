import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easyplay/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const kataGo = MethodChannel('easyplay/katago');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kataGo, (call) async => '');
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kataGo, null);
  });

  testWidgets('home shows all game types', (tester) async {
    await tester.pumpWidget(const EasyPlayApp());
    expect(find.text('围棋'), findsOneWidget);
    expect(find.text('国际象棋'), findsOneWidget);
    expect(find.text('跳棋'), findsOneWidget);
    expect(find.text('未完成'), findsNWidgets(2));
    expect(find.text('每日题目'), findsNothing);
    expect(find.text('积分'), findsNothing);
    expect(find.text('棋手 001'), findsNothing);
  });

  testWidgets('unfinished games cannot be opened', (tester) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.text('国际象棋'));
    await tester.pumpAndSettle();
    expect(find.text('今天，\n来一局好棋。'), findsOneWidget);
    expect(find.text('黑方回合'), findsNothing);

    await tester.tap(find.text('跳棋'));
    await tester.pumpAndSettle();
    expect(find.text('今天，\n来一局好棋。'), findsOneWidget);
  });

  testWidgets('settings expose appearance and bundled licenses', (
    tester,
  ) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('外观显示'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );

    await tester.tap(find.text('关于 EasyPlay'));
    await tester.pumpAndSettle();
    expect(find.text('KataGo 神经网络模型'), findsOneWidget);
    await tester.tap(find.text('KataGo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('KataGo'), findsWidgets);
  });

  testWidgets('can open a new Go game', (tester) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.text('围棋'));
    await tester.pumpAndSettle();
    expect(find.text('新建 AI 对局'), findsOneWidget);
    expect(find.text('KataGo b6 小模型'), findsOneWidget);
    expect(find.text('5k'), findsOneWidget);
    await tester.tap(find.text('开始对局'));
    await tester.pump();
    await tester.pump();
    expect(find.text('黑方回合'), findsOneWidget);
    expect(find.text('电脑（KataGo 5k）'), findsOneWidget);
    expect(find.text('重新开始'), findsOneWidget);
  });

  testWidgets('unavailable KataGo falls back to local play', (tester) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.text('围棋'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我执白'));
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('黑方回合'), findsOneWidget);
    expect(find.text('本地双人'), findsOneWidget);
    expect(find.text('电脑思考中…'), findsNothing);
  });
}
