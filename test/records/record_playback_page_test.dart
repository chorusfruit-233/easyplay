import 'dart:convert';
import 'dart:async';

import 'package:easyplay/board.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_library_page.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_library_page.dart';
import 'package:easyplay/go_storage.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/gomoku/widgets/gomoku_library_page.dart';
import 'package:easyplay/gomoku/widgets/gomoku_game_page.dart';
import 'package:easyplay/records/record_replay.dart';
import 'package:easyplay/records/widgets/record_playback_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedPlayer extends GomokuAi {
  final requests = <Completer<GomokuAction?>>[];

  @override
  Future<GomokuAction?> decide(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
  }) {
    final request = Completer<GomokuAction?>();
    requests.add(request);
    return request.future;
  }

  @override
  void cancel() {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  GomokuRecord gomoku() => GomokuRecord(
    id: 'playback',
    createdAt: DateTime.utc(2026),
    session: GomokuSession()
      ..place(const Cell(7, 7))
      ..place(const Cell(6, 7))
      ..place(const Cell(5, 7)),
  );

  Future<void> press(WidgetTester tester, String action) async {
    final button = find.byKey(ValueKey('record-playback-$action'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  testWidgets(
    'opening current-game playback rejects stale AI and resumes only on return',
    (tester) async {
      final session = GomokuSession(variant: GomokuVariant.freestyle)
        ..place(const Cell(7, 7));
      final ai = _DelayedPlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: GomokuGamePage(
            session: session,
            aiLevel: GomokuAiLevel.beginner,
            ai: ai,
          ),
        ),
      );
      await tester.pump();
      expect(ai.requests, hasLength(1));
      await tester.tap(find.byTooltip('播放棋谱'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordPlaybackPage), findsOneWidget);
      ai.requests.first.complete(const GomokuAction.place(Cell(6, 7)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(session.moves, hasLength(1));
      expect(ai.requests, hasLength(1));
      await press(tester, 'last');
      expect(session.moves, hasLength(1));
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ai.requests, hasLength(2));
      ai.requests.last.complete(const GomokuAction.place(Cell(6, 7)));
      await tester.pumpAndSettle();
      expect(session.moves, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('playback is read-only and pauses across background/resume', (
    tester,
  ) async {
    final source = gomoku();
    final original = source.toJson();
    await tester.pumpWidget(
      MaterialApp(home: RecordPlaybackPage(record: GomokuRecordReplay(source))),
    );
    await tester.pumpAndSettle();
    int moves() => tester
        .widget<GomokuBoard>(find.byType(GomokuBoard))
        .session
        .moves
        .length;
    expect(moves(), 0);
    expect(
      tester.widget<GomokuBoard>(find.byType(GomokuBoard)).enabled,
      isFalse,
    );
    await tester.tapAt(tester.getCenter(find.byType(GomokuBoard)));
    expect(moves(), 0);
    await press(tester, 'toggle');
    await tester.pump(const Duration(seconds: 1));
    expect(moves(), 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(moves(), 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(moves(), 1);
    await press(tester, 'toggle');
    await tester.pump(const Duration(seconds: 1));
    expect(moves(), 2);
    await press(tester, 'previous');
    await tester.pump(const Duration(seconds: 2));
    expect(moves(), 1);
    await press(tester, 'last');
    expect(moves(), 3);
    expect(find.textContaining('播放完毕'), findsOneWidget);
    final slider = find.byKey(const ValueKey('record-playback-slider'));
    await tester.ensureVisible(slider);
    await tester.tapAt(tester.getCenter(slider));
    await tester.pump();
    expect(moves(), 2);
    await press(tester, 'last');
    expect(source.toJson(), original);
    await press(tester, 'toggle');
    expect(moves(), 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SGF branch selection changes the played line and keeps comments',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecordPlaybackPage(
            record: GoRecordReplay(
              '(;GM[1]SZ[9];B[aa](;W[bb]C[main])(;W[cc]C[alternative]))',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, 'last');
      expect(find.text('main'), findsOneWidget);
      final choice = find.byKey(const ValueKey('record-playback-variation'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('变化 1').last);
      await tester.pumpAndSettle();
      await press(tester, 'last');
      final board = tester.widget<Board>(find.byType(Board)).session.board;
      expect(board[2][2]?.side, Side.white);
      expect(board[1][1], isNull);
      expect(find.text('alternative'), findsOneWidget);
    },
  );

  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('controls remain reachable at $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2.5)),
            child: child!,
          ),
          home: RecordPlaybackPage(record: GomokuRecordReplay(gomoku())),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, 'next');
      expect(
        tester.widget<GomokuBoard>(find.byType(GomokuBoard)).session.moves,
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final game in ['go', 'gomoku', 'draughts']) {
    testWidgets(
      '$game library playback leaves storage byte-for-byte unchanged',
      (tester) async {
        late Widget library;
        if (game == 'go') {
          await GoStorage.addRecord(
            '(;GM[1]SZ[9];B[aa];W[bb])',
            vsComputer: true,
          );
          library = const GoLibraryPage();
        } else if (game == 'gomoku') {
          await GomokuStorage.save(gomoku());
          library = const GomokuLibraryPage();
        } else {
          final session = DraughtsSession(
            DraughtsRules.forVariant(DraughtsVariant.english),
          );
          for (var i = 0; i < 3; i++) {
            session.applyMove(session.legalMoves().first);
          }
          await DraughtsStorage.save(DraughtsRecord.fromSession(session));
          library = const DraughtsLibraryPage();
        }
        final prefs = await SharedPreferences.getInstance();
        Map<String, Object?> storage() => {
          for (final key in prefs.getKeys()) key: prefs.get(key),
        };
        final before = jsonEncode(storage());
        await tester.pumpWidget(MaterialApp(home: library));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('播放棋谱').first);
        await tester.pumpAndSettle();
        expect(find.byType(RecordPlaybackPage), findsOneWidget);
        await press(tester, 'last');
        await press(tester, 'first');
        await press(tester, 'toggle');
        await tester.pump(const Duration(seconds: 1));
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        expect(jsonEncode(storage()), before);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
