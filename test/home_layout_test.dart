import 'package:easyplay/app_theme.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/game_page.dart' show GameTypeX;
import 'package:easyplay/home_page.dart';
import 'package:easyplay/chess/widgets/chess_lan_pages.dart';
import 'package:easyplay/lan/lan_quick_join.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget home({
  double textScale = 1,
  Brightness brightness = Brightness.light,
  ValueChanged<GameType>? onPlay,
}) => MaterialApp(
  theme: AppTheme.fromScheme(
    ColorScheme.fromSeed(
      seedColor: AppTheme.defaultSeed,
      brightness: brightness,
    ),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SafeArea(
      child: HomePage(onPlay: onPlay ?? (_) {}, onSettings: () {}),
    ),
  ),
);

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(568, 320),
    const Size(1280, 800),
  ]) {
    for (final textScale in [1.0, 1.8]) {
      testWidgets('all six games remain reachable at $size, text $textScale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final opened = <GameType>[];
        await tester.pumpWidget(home(textScale: textScale, onPlay: opened.add));
        expect(find.byType(GameCard), findsNWidgets(6));
        for (final game in GameType.values) {
          await tester.ensureVisible(find.text(game.label));
          await tester.tap(find.text(game.label));
          await tester.pumpAndSettle();
        }
        expect(opened, GameType.values);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('phone grid is two columns, desktop grid is three', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (size, columns) in [
      (const Size(390, 844), 2),
      (const Size(1280, 800), 3),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      final cards = find.byType(GameCard);
      expect(
        tester.getTopLeft(cards.at(0)).dy,
        tester.getTopLeft(cards.at(columns - 1)).dy,
      );
      expect(
        tester.getTopLeft(cards.at(columns)).dy,
        greaterThan(tester.getTopLeft(cards.at(0)).dy),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'game cards can be opened with keyboard and expose a tap action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      GameType? opened;
      await tester.pumpWidget(home(onPlay: (game) => opened = game));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Settings.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // First game.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, GameType.go);
      expect(
        tester.getSemantics(find.byType(GameCard).first),
        matchesSemantics(
          label: '围棋，布局与收官，一步一步来',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          isFocused: true,
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets('dark theme keeps the game entries readable', (tester) async {
    await tester.pumpWidget(home(brightness: Brightness.dark));
    for (final game in GameType.values) {
      await tester.ensureVisible(find.text(game.label));
      expect(find.text(game.label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('LAN menu cards have separation and wide forms stay bounded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromScheme(
          ColorScheme.fromSeed(seedColor: AppTheme.defaultSeed),
        ),
        home: const ChessLanLobbyPage(),
      ),
    );
    final first = tester.getRect(find.widgetWithText(ListTile, '创建房间'));
    final second = tester.getRect(find.widgetWithText(ListTile, '加入房间'));
    expect(second.top - first.bottom, greaterThanOrEqualTo(12));
    expect(first.width, lessThan(760));
    expect(first.center.dx, 640);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host quick join remains usable with enlarged text on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromScheme(
          ColorScheme.fromSeed(seedColor: AppTheme.defaultSeed),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LanQuickJoinCard(
              loadRoom: () async => LanWebRoom(
                Uri.parse('http://192.168.1.2:8087'),
                'chess',
                null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('快捷加入'));
    await tester.tap(find.text('快捷加入'));
    await tester.pumpAndSettle();
    expect(find.byType(LanQuickJoinPage), findsOneWidget);
    expect(find.widgetWithText(TextField, '房间口令'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
