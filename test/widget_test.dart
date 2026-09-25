import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:easyplay/main.dart';

void main() {
  const kataGo = MethodChannel('easyplay/katago');
  setUp(() {
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

  testWidgets('can open a new Go game', (tester) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.text('围棋'));
    await tester.pumpAndSettle();
    expect(find.text('围棋设置'), findsOneWidget);
    await tester.tap(find.text('开始对局'));
    await tester.pump();
    await tester.pump();
    expect(find.text('黑方回合'), findsOneWidget);
    expect(find.text('电脑（KataGo b6）'), findsOneWidget);
    expect(find.text('重新开始'), findsOneWidget);
  });
}
