import 'package:easyplay/ai/ai_duel_config.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_ai_duel_page.dart';
import 'package:easyplay/draughts/widgets/draughts_board.dart';
import 'package:easyplay/draughts/widgets/draughts_new_game_page.dart';
import 'package:easyplay/game_session.dart' show Cell;
import 'package:easyplay/gomoku/gomoku_ai_level.dart';
import 'package:easyplay/gomoku/gomoku_ai.dart' show GomokuAi;
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:easyplay/gomoku/widgets/gomoku_ai_duel_page.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/gomoku/widgets/gomoku_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const gomokuConfig = AiDuelConfig(
  blackLevel: GomokuAiLevel.beginner,
  whiteLevel: GomokuAiLevel.beginner,
);
const draughtsConfig = AiDuelConfig(
  blackLevel: DraughtsAiLevel.beginner,
  whiteLevel: DraughtsAiLevel.beginner,
);

Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final draughts in [false, true]) {
    final game = draughts ? 'Draughts' : 'Gomoku';

    testWidgets('$game home starts spectator mode with independent levels', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: draughts ? const DraughtsNewGamePage() : const GomokuHomePage(),
        ),
      );
      await tester.scrollUntilVisible(find.text('AI 对抗'), 300);
      await tester.tap(find.text('AI 对抗'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('duel-black-level')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('高级').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('duel-white-level')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('初级').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始观战'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('暂停'));
      await tester.pumpAndSettle();
      if (draughts) {
        final page = tester.widget<DraughtsAiDuelPage>(
          find.byType(DraughtsAiDuelPage),
        );
        expect(page.config.blackLevel, DraughtsAiLevel.advanced);
        expect(page.config.whiteLevel, DraughtsAiLevel.beginner);
      } else {
        final page = tester.widget<GomokuAiDuelPage>(
          find.byType(GomokuAiDuelPage),
        );
        expect(page.config.blackLevel, GomokuAiLevel.advanced);
        expect(page.config.whiteLevel, GomokuAiLevel.beginner);
      }
      expect(
        find.text(draughts ? '黑方 AI · 高级' : '先手（执黑方） AI · 高级'),
        findsOneWidget,
      );
      expect(
        find.text(draughts ? '白方 AI · 初级' : '后手（执白方） AI · 初级'),
        findsOneWidget,
      );
      expect(find.text('继续'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('AI 对抗 · 黑高级 / 白初级'), findsOneWidget);
      await tester.tap(find.textContaining('AI 对抗 · 黑高级 / 白初级'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已暂停'), findsOneWidget);
      expect(find.text('继续'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    for (final size in [const Size(360, 640), const Size(640, 360)]) {
      testWidgets('$game spectator controls and board fit $size', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: draughts
                ? DraughtsAiDuelPage(
                    session: DraughtsSession(
                      DraughtsRules.forVariant(DraughtsVariant.international),
                    ),
                    config: draughtsConfig,
                    initiallyPaused: true,
                  )
                : GomokuAiDuelPage(
                    ai: GomokuAi(),
                    session: GomokuSession(variant: GomokuVariant.renju),
                    config: gomokuConfig,
                    initiallyPaused: true,
                  ),
          ),
        );
        await tester.pumpAndSettle();
        final board = find.byType(draughts ? DraughtsBoard : GomokuBoard);
        final rect = tester.getRect(board);
        expect(rect.width, greaterThan(150));
        expect(rect.height, greaterThan(150));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        for (final label in ['继续', '单步', '悔棋', '重开']) {
          await tester.ensureVisible(find.text(label));
          expect(
            tester.getRect(find.text(label)).bottom,
            lessThanOrEqualTo(size.height),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets(
      '$game single step, lifecycle, undo and restart retain user pause',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(420, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: draughts
                ? DraughtsAiDuelPage(
                    session: DraughtsSession(
                      DraughtsRules.forVariant(DraughtsVariant.english),
                    ),
                    config: draughtsConfig,
                    initiallyPaused: true,
                  )
                : GomokuAiDuelPage(
                    ai: GomokuAi(),
                    session: GomokuSession(variant: GomokuVariant.freestyle),
                    config: gomokuConfig,
                    initiallyPaused: true,
                  ),
          ),
        );
        await tester.pumpAndSettle();
        int moves() => draughts
            ? tester
                  .widget<DraughtsBoard>(find.byType(DraughtsBoard))
                  .session
                  .moves
                  .length
            : tester
                  .widget<GomokuBoard>(find.byType(GomokuBoard))
                  .session
                  .moves
                  .length;
        // Spectators cannot place stones or move a piece directly.
        await tester.tapAt(
          tester.getCenter(find.byType(draughts ? DraughtsBoard : GomokuBoard)),
        );
        expect(moves(), 0);
        await tester.tap(find.text('单步'));
        await drain(tester);
        expect(moves(), 1);
        expect(find.text('继续'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await drain(tester);
        expect(moves(), 1);
        await tester.tap(find.text('继续'));
        await drain(tester);
        await tester.tap(find.text('暂停'));
        await drain(tester);
        expect(moves(), greaterThanOrEqualTo(2));
        final beforeUndo = moves();
        await tester.tap(find.text('悔棋'));
        await drain(tester);
        expect(moves(), beforeUndo - 1);
        expect(find.text('继续'), findsOneWidget);
        await tester.tap(find.text('重开'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('重新开始'));
        await tester.pumpAndSettle();
        expect(moves(), 0);
        expect(find.text('继续'), findsOneWidget);
        await tester.tap(find.text('重开'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(moves(), 0);
        expect(find.text('继续'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        if (draughts) {
          expect(await DraughtsStorage.list(), hasLength(2));
        } else {
          expect(await GomokuStorage.list(), hasLength(2));
        }
      },
    );
  }

  testWidgets(
    'finished Gomoku duel restores its result without restarting AI',
    (tester) async {
      final session = GomokuSession()..place(const Cell(7, 7));
      session.resign(session.turn);
      await GomokuStorage.save(
        GomokuRecord(
          id: 'finished',
          createdAt: DateTime.utc(2026),
          session: session,
          aiDuel: gomokuConfig,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: GomokuHomePage()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('AI 对抗 · 黑初级 / 白初级'),
        300,
      );
      await tester.ensureVisible(find.textContaining('AI 对抗 · 黑初级 / 白初级'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('AI 对抗 · 黑初级 / 白初级'));
      await tester.pumpAndSettle();
      expect(find.text(session.resultLabel), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '单步'))
            .onPressed,
        isNull,
      );
      await drain(tester);
      final restored = tester
          .widget<GomokuBoard>(find.byType(GomokuBoard))
          .session;
      expect(restored.gameOver, isTrue);
      expect(restored.moves, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
