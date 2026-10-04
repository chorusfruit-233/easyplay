import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easyplay/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyplay/go_placement.dart';
import 'package:easyplay/gomoku/gomoku_variant.dart';
import 'package:easyplay/gomoku/widgets/gomoku_lan_pages.dart';

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
    expect(find.text('五子棋'), findsOneWidget);
    expect(find.text('未完成'), findsNothing);
    expect(find.text('每日题目'), findsNothing);
    expect(find.text('积分'), findsNothing);
    expect(find.text('棋手 001'), findsNothing);
  });

  testWidgets('Chess opens its home and Draughts opens the variant picker', (
    tester,
  ) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.text('国际象棋'));
    await tester.pumpAndSettle();
    expect(find.text('本地双人'), findsOneWidget);
    expect(find.text('AI 对战'), findsOneWidget);
    expect(find.text('黑方回合'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳棋'));
    await tester.pumpAndSettle();
    expect(find.text('Checkers / Draughts'), findsOneWidget);
    expect(find.text('英式 / 美式'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('本地双人对局'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('本地双人对局'), findsOneWidget);
    expect(find.text('局域网联机'), findsOneWidget);
  });

  testWidgets('settings expose appearance and bundled licenses', (
    tester,
  ) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题设置'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('跟随系统'), findsOneWidget);
    expect(find.byTooltip('浅色'), findsOneWidget);
    expect(find.byTooltip('深色'), findsOneWidget);

    await tester.tap(find.byTooltip('深色'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于 EasyPlay'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('KataGo 神经网络模型'), 150);
    expect(find.text('KataGo 神经网络模型'), findsOneWidget);
    await tester.tap(find.text('KataGo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('KataGo'), findsWidgets);
  });

  testWidgets('Gomoku opens local, AI and network entries from home', (
    tester,
  ) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.ensureVisible(find.text('五子棋'));
    await tester.tap(find.text('五子棋'));
    await tester.pumpAndSettle();
    expect(find.text('GOMOKU'), findsOneWidget);
    expect(find.text('本地双人'), findsOneWidget);
    expect(find.text('人机对弈'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<GomokuVariant>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连珠禁手').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('联机对弈'));
    await tester.tap(find.text('联机对弈'));
    await tester.pumpAndSettle();
    expect(find.text('五子棋联机'), findsOneWidget);
    expect(
      tester
          .widget<GomokuLanLobbyPage>(find.byType(GomokuLanLobbyPage))
          .variant,
      GomokuVariant.renju,
    );
    expect(find.text('创建房间'), findsOneWidget);
    expect(find.text('加入房间'), findsOneWidget);
  });

  testWidgets('placement mode settings persist a selection', (tester) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final placement = find.text('落子模式');
    await tester.scrollUntilVisible(
      placement,
      300,
      scrollable: find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(placement);
    await tester.pumpAndSettle();
    expect(find.text('落子模式设置'), findsOneWidget);
    expect(find.text('自动'), findsOneWidget);
    await tester.tap(find.text('滑动确认'));
    await tester.pumpAndSettle();
    expect(await GoPlacementPreferences.load(), GoPlacementMode.swipeConfirm);
  });

  testWidgets('can open a new Go game', (tester) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.tap(find.text('围棋'));
    await tester.pumpAndSettle();
    // Go opens on its own home page now, so the game is one step further in.
    await tester.tap(find.text('AI 对弈'));
    await tester.pumpAndSettle();
    expect(find.text('新建 AI 对局'), findsOneWidget);
    // The engine profile decides which networks to load; the setup dialog has
    // no model picker to assert on.
    expect(find.text('引擎'), findsOneWidget);
    expect(find.text('5k'), findsOneWidget);
    // The engine field doubles as "is anyone playing the other colour".
    expect(find.text('不下棋（仅记录）'), findsNothing);
    await tester.tap(find.text('开始对局'));
    await tester.pump();
    await tester.pump();
    expect(find.text('黑方回合'), findsOneWidget);
    // The engine choice is summarised in the toolbar's robot panel now, so the
    // state card no longer repeats the mode.
    expect(find.text('重新开始'), findsOneWidget);
    expect(find.byTooltip('AI 与复盘'), findsOneWidget);
  });

  // There is no local-play mode to fall back to: the engine is the only
  // opponent, so an unavailable engine must stop the computer rather than
  // silently switch the game to two humans.
  testWidgets(
    'unavailable engine stops the computer instead of switching mode',
    (tester) async {
      await tester.pumpWidget(const EasyPlayApp());
      await tester.tap(find.text('围棋'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 对弈'));
      await tester.pumpAndSettle();
      final white = find.widgetWithText(ChoiceChip, '我执白');
      await tester.ensureVisible(white);
      await tester.tap(white);
      await tester.tap(find.text('开始对局'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(find.text('黑方回合'), findsOneWidget);
      expect(find.text('电脑思考中…'), findsNothing);
      expect(find.text('本地双人'), findsNothing);
    },
  );
}
