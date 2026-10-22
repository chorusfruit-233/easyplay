import 'dart:convert';

import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_game_page.dart';
import 'package:easyplay/draughts/widgets/draughts_library_page.dart';
import 'package:easyplay/draughts/widgets/draughts_new_game_page.dart';
import 'package:easyplay/game_session.dart' show Side;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/record_file_picker.dart';

DraughtsRecord record({String id = 'game', int plies = 2}) {
  final session = DraughtsSession(
    DraughtsRules.forVariant(DraughtsVariant.english),
  );
  for (var i = 0; i < plies; i++) {
    session.applyMove(session.legalMoves().first);
  }
  return DraughtsRecord.fromSession(
    session,
    id: id,
    createdAt: DateTime.utc(2026, 10, 18),
  );
}

void main() {
  late MemoryRecordFilePicker picker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    picker = MemoryRecordFilePicker();
    FilePicker.platform = picker;
  });

  testWidgets('home opens the dedicated library and empty import action', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DraughtsNewGamePage()));
    expect(find.text('最近对局'), findsNothing);
    await tester.scrollUntilVisible(find.text('棋谱库'), 300);
    await tester.tap(find.text('棋谱库'));
    await tester.pumpAndSettle();
    expect(find.byType(DraughtsLibraryPage), findsOneWidget);
    expect(find.text('还没有棋谱'), findsOneWidget);
    expect(find.byTooltip('导入 PDN 棋谱'), findsOneWidget);
  });

  testWidgets('library opens records beyond the old twenty-row preview', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'easyplay.draughts.records.v1': jsonEncode([
        for (var i = 0; i < 25; i++) record(id: 'game-$i').toJson(),
      ]),
    });
    await tester.pumpWidget(const MaterialApp(home: DraughtsLibraryPage()));
    await tester.pumpAndSettle();
    final oldest = find.byKey(const ValueKey('draughts-record-game-24'));
    await tester.scrollUntilVisible(oldest, 400);
    await tester.tap(oldest);
    await tester.pumpAndSettle();
    final game = tester.widget<DraughtsGamePage>(find.byType(DraughtsGamePage));
    expect(game.recordId, 'game-24');
    expect(game.session.moves, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PDN export downloads the selected moves, variant and result', (
    tester,
  ) async {
    final source = record(id: 'saved/game');
    final session = source.restore()..resign(Side.white);
    final finished = DraughtsRecord.fromSession(
      session,
      id: source.id,
      createdAt: source.createdAt,
    );
    await DraughtsStorage.save(finished);
    await tester.pumpWidget(const MaterialApp(home: DraughtsLibraryPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('棋谱操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出 PDN'));
    await tester.pumpAndSettle();
    expect(
      picker.savedFileName,
      'checkers_english_20261018T000000000Z_saved_game.pdn',
    );
    expect(picker.savedExtensions, ['pdn']);
    final pdn = utf8.decode(picker.savedBytes!);
    expect(pdn, contains('[Variant "English"]'));
    expect(pdn, contains('[Result "1-0"]'));
    expect(DraughtsNotation.importPdn(pdn).moves, source.moves);
    expect(find.text('棋谱已导出'), findsOneWidget);
    expect(await DraughtsStorage.list(), hasLength(1));
  });

  for (final fails in [false, true]) {
    testWidgets('export ${fails ? 'failure' : 'cancellation'} is reported', (
      tester,
    ) async {
      picker.cancelled = !fails;
      if (fails) picker.saveError = StateError('disk full');
      await DraughtsStorage.save(record());
      await tester.pumpWidget(const MaterialApp(home: DraughtsLibraryPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('棋谱操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 PDN'));
      await tester.pumpAndSettle();
      expect(find.text('棋谱已导出'), findsNothing);
      expect(find.textContaining(fails ? '导出失败' : '已取消导出'), findsOneWidget);
      expect(await DraughtsStorage.list(), hasLength(1));
    });
  }

  testWidgets('delete requires confirmation and cancellation keeps the game', (
    tester,
  ) async {
    await DraughtsStorage.save(record());
    await tester.pumpWidget(const MaterialApp(home: DraughtsLibraryPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('棋谱操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除棋谱'));
    await tester.pumpAndSettle();
    expect(find.text('删除棋谱？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await DraughtsStorage.list(), hasLength(1));
    await tester.tap(find.byTooltip('棋谱操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除棋谱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await DraughtsStorage.list(), isEmpty);
    expect(find.text('还没有棋谱'), findsOneWidget);
  });

  testWidgets('library reports storage failure and retries loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'easyplay.draughts.records.v1': 'not json',
    });
    await tester.pumpWidget(const MaterialApp(home: DraughtsLibraryPage()));
    await tester.pumpAndSettle();
    expect(find.text('棋谱加载失败'), findsOneWidget);
    SharedPreferences.setMockInitialValues({});
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('还没有棋谱'), findsOneWidget);
  });

  testWidgets('PDN import remains accessible from the library', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DraughtsLibraryPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导入 PDN 棋谱'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      DraughtsNotation.exportPdn(record()),
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.text('棋谱已导入'), findsOneWidget);
    expect((await DraughtsStorage.list()).single.moves, record().moves);
  });

  testWidgets('library export and menu fit a narrow display', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await DraughtsStorage.save(record());
    await tester.pumpWidget(const MaterialApp(home: DraughtsLibraryPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final tooltip in ['播放棋谱', '棋谱操作']) {
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.width, greaterThanOrEqualTo(48));
    }
  });
}
