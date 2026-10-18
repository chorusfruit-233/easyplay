import 'dart:convert';

import 'package:easyplay/game_session.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:easyplay/gomoku/widgets/gomoku_home_page.dart';
import 'package:easyplay/gomoku/widgets/gomoku_library_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/record_file_picker.dart';

GomokuRecord _record(String id) => GomokuRecord(
  id: id,
  createdAt: DateTime.utc(2026, 10, 18),
  session: GomokuSession()..place(const Cell(7, 7)),
);

Future<void> _menu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('棋谱操作').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  late MemoryRecordFilePicker picker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    picker = MemoryRecordFilePicker();
    FilePicker.platform = picker;
  });

  testWidgets('home opens a dedicated library with an empty state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GomokuHomePage()));
    await tester.pumpAndSettle();
    expect(find.text('最近对局'), findsNothing);
    await tester.ensureVisible(find.text('棋谱库'));
    await tester.tap(find.text('棋谱库'));
    await tester.pumpAndSettle();
    expect(find.byType(GomokuLibraryPage), findsOneWidget);
    expect(find.text('还没有棋谱'), findsOneWidget);
    expect(find.byTooltip('棋谱操作'), findsNothing);
  });

  testWidgets(
    'all library entries remain reachable beyond twenty recent games',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        GomokuStorage.key: jsonEncode([
          for (var index = 0; index < 35; index++) _record('$index').toJson(),
        ]),
      });
      await tester.pumpWidget(const MaterialApp(home: GomokuLibraryPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('35 份棋谱'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('gomoku-record-34')),
        400,
      );
      expect(find.byKey(const ValueKey('gomoku-record-34')), findsOneWidget);
      expect(await GomokuStorage.list(), hasLength(35));
    },
  );

  testWidgets(
    'exports actual UTF-8 SGF and complete JSON without changing the record',
    (tester) async {
      final record = _record('export');
      await GomokuStorage.save(record);
      await tester.pumpWidget(const MaterialApp(home: GomokuLibraryPage()));
      await tester.pumpAndSettle();
      await _menu(tester, '导出 SGF');
      expect(picker.savedFileName, endsWith('.sgf'));
      expect(picker.savedExtensions, ['sgf']);
      expect(utf8.decode(picker.savedBytes!), contains('GM[4]'));
      expect(utf8.decode(picker.savedBytes!), contains(';B[hh])'));
      expect(find.text('SGF 棋谱已导出'), findsOneWidget);
      await _menu(tester, '导出 JSON 完整备份');
      expect(picker.savedFileName, endsWith('.json'));
      expect(picker.savedExtensions, ['json']);
      final exported = jsonDecode(utf8.decode(picker.savedBytes!));
      expect(GomokuRecord.fromJson(exported).toJson(), record.toJson());
      expect(find.text('JSON 完整备份已导出'), findsOneWidget);
      expect((await GomokuStorage.list()).single.toJson(), record.toJson());
    },
  );

  testWidgets(
    'cancelled export has no success notice; failure remains retryable',
    (tester) async {
      await GomokuStorage.save(_record('cancel'));
      await tester.pumpWidget(const MaterialApp(home: GomokuLibraryPage()));
      await tester.pumpAndSettle();
      picker.cancelled = true;
      await _menu(tester, '导出 SGF');
      expect(find.text('SGF 棋谱已导出'), findsNothing);
      picker.cancelled = false;
      picker.saveError = StateError('no space');
      await _menu(tester, '导出 JSON 完整备份');
      expect(find.textContaining('棋谱导出失败'), findsOneWidget);
      picker.saveError = null;
      await _menu(tester, '导出 JSON 完整备份');
      expect(find.text('JSON 完整备份已导出'), findsOneWidget);
      expect(await GomokuStorage.list(), hasLength(1));
    },
  );

  testWidgets(
    'delete needs confirmation and only removes the selected record',
    (tester) async {
      await GomokuStorage.save(_record('keep'));
      await GomokuStorage.save(_record('delete'));
      await tester.pumpWidget(const MaterialApp(home: GomokuLibraryPage()));
      await tester.pumpAndSettle();
      await _menu(tester, '删除棋谱');
      expect(find.text('删除棋谱？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await GomokuStorage.list(), hasLength(2));
      await _menu(tester, '删除棋谱');
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect((await GomokuStorage.list()).map((record) => record.id), ['keep']);
      expect(find.text('棋谱已删除'), findsOneWidget);
    },
  );
}
