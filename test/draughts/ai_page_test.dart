import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_board.dart';
import 'package:easyplay/draughts/widgets/draughts_game_page.dart';
import 'package:easyplay/draughts/widgets/draughts_new_game_page.dart';
import 'package:easyplay/game_session.dart' show Side;

Future<void> drainSearch(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'reopened AI records refresh after play and retain the new history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.english),
      );
      original.applyMove(original.legalMoves().first);
      original.applyMove(original.legalMoves().first);
      await DraughtsStorage.save(
        DraughtsRecord.fromSession(
          original,
          id: 'resume-ai',
          kind: DraughtsGameKind.ai,
          localSide: Side.black,
          aiLevel: DraughtsAiLevel.beginner,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: DraughtsNewGamePage()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.textContaining('人机 · 初级'), 300);
      await tester.tap(find.textContaining('人机 · 初级'));
      await tester.pumpAndSettle();
      final page = tester.widget<DraughtsGamePage>(
        find.byType(DraughtsGamePage),
      );
      expect(page.aiLevel, DraughtsAiLevel.beginner);
      expect(page.humanSide, Side.black);
      final move = page.session.legalMoves().first;
      final view = tester.widget<DraughtsBoard>(find.byType(DraughtsBoard));
      view.onCell(move.from);
      for (final cell in move.path.skip(1)) {
        view.onCell(cell);
      }
      await drainSearch(tester);
      expect(page.session.moves.length, 4);
      Navigator.of(tester.element(find.byType(DraughtsGamePage))).pop();
      await tester.pumpAndSettle();
      expect(find.textContaining('人机 · 初级 · 4 手'), findsOneWidget);
      await tester.tap(find.textContaining('人机 · 初级 · 4 手'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DraughtsGamePage>(find.byType(DraughtsGamePage))
            .session
            .moves
            .length,
        4,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('AI setup offers difficulty and side selection', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DraughtsNewGamePage()));
    await tester.scrollUntilVisible(find.text('人机对弈'), 300);
    await tester.tap(find.text('人机对弈'));
    await tester.pumpAndSettle();
    expect(find.text('执棋方'), findsOneWidget);
    expect(find.text('难度'), findsOneWidget);
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();
    expect(find.byType(DraughtsGamePage), findsOneWidget);
    final page = tester.widget<DraughtsGamePage>(find.byType(DraughtsGamePage));
    expect(page.aiLevel, DraughtsAiLevel.intermediate);
    expect(page.humanSide, page.session.rules.firstMove);
    await tester.pumpWidget(const SizedBox());
    await drainSearch(tester);
  });

  testWidgets(
    'undo during AI search cancels the reply and restores human turn',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.english),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DraughtsGamePage(
            session: session,
            aiLevel: DraughtsAiLevel.beginner,
            humanSide: Side.black,
          ),
        ),
      );
      final initial = session.position.signature(session.turn);
      expect(
        tester.widget<DraughtsBoard>(find.byType(DraughtsBoard)).flipped,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('draughts-square-2-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('draughts-square-3-0')));
      expect(session.moves.length, 1);
      await tester.pump();
      await tester.ensureVisible(find.text('悔棋'));
      await tester.tap(find.text('悔棋'));
      await drainSearch(tester);
      expect(session.moves, isEmpty);
      expect(session.position.signature(session.turn), initial);
      expect(find.text('AI 正在思考…'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('draughts-square-2-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('draughts-square-3-0')));
      await drainSearch(tester);
      expect(session.moves.length, 2);
      await tester.tap(find.text('悔棋'));
      await drainSearch(tester);
      expect(session.moves, isEmpty);
      expect(session.position.signature(session.turn), initial);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AI opening pauses in background, resumes and cancels on disposal',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.english),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DraughtsGamePage(
            session: session,
            aiLevel: DraughtsAiLevel.beginner,
            humanSide: Side.white,
          ),
        ),
      );
      // The human cannot move the opponent's pieces while it is thinking.
      await tester.tap(find.byKey(const ValueKey('draughts-square-2-1')));
      expect(
        tester.widget<DraughtsBoard>(find.byType(DraughtsBoard)).selected,
        isNull,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await drainSearch(tester);
      expect(session.moves, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await drainSearch(tester);
      expect(session.moves.length, 1);
      expect(session.turn, Side.white);
      // Start another AI reply and immediately close the page.
      final human = session.legalMoves().first;
      session.applyMove(human);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await drainSearch(tester);
      expect(session.moves.length, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
