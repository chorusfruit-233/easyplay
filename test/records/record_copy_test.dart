import 'dart:convert';

import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_library_page.dart';
import 'package:easyplay/go_library_page.dart';
import 'package:easyplay/go_storage.dart';
import 'package:easyplay/gomoku/gomoku_notation.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:easyplay/gomoku/widgets/gomoku_library_page.dart';
import 'package:easyplay/records/board_record.dart';
import 'package:easyplay/records/board_record_notation.dart';
import 'package:easyplay/records/board_record_storage.dart';
import 'package:easyplay/records/widgets/board_library_page.dart';
import 'package:easyplay/records/widgets/record_copy.dart';
import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/record_file_picker.dart';

typedef _Fixture = ({Widget page, Map<String, String> copies});

Future<_Fixture> _fixture(String game) async {
  if (game == 'go') {
    final record = await GoStorage.addRecord(
      '(;GM[1]FF[4]SZ[9]C[分享棋谱 ✓]AB[aa]PL[W]'
      ';W[dd](;B[ff]C[主线])(;B[ee]C[另一条变化]))',
    );
    return (page: const GoLibraryPage(), copies: {'复制 SGF': record.sgf});
  }
  if (game == 'gomoku') {
    final session = GomokuSession()
      ..place(const Cell(7, 7))
      ..place(const Cell(6, 7))
      ..place(const Cell(5, 7))
      ..exchangeColors(true)
      ..place(const Cell(9, 7))
      ..declareProposals(2)
      ..exchangeColors(false)
      ..place(const Cell(6, 6))
      ..place(const Cell(7, 5))
      ..place(const Cell(7, 5))
      ..pass()
      ..pass();
    final record = GomokuRecord(
      id: 'copy',
      createdAt: DateTime.utc(2026),
      session: session,
    );
    await GomokuStorage.save(record);
    return (
      page: const GomokuLibraryPage(),
      copies: {
        '复制 SGF': GomokuNotation.toSgf(record),
        '复制 JSON 完整备份': GomokuNotation.toJson(record),
      },
    );
  }
  if (game == 'draughts') {
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.international),
    );
    for (var i = 0; i < 4; i++) {
      session.applyMove(session.legalMoves().first);
    }
    session.agreeDraw();
    final record = DraughtsRecord.fromSession(session, id: 'copy');
    await DraughtsStorage.save(record);
    return (
      page: const DraughtsLibraryPage(),
      copies: {'复制 PDN': DraughtsNotation.exportPdn(record)},
    );
  }
  final BoardGameRecord record;
  if (game == 'chess') {
    final session = ChessSession()
      ..applyMove(parseUciMove('e2e4'))
      ..applyMove(parseUciMove('e7e5'))
      ..resign(Side.black);
    record = BoardGameRecord.fromChess(session, id: 'copy');
  } else {
    final session = XiangqiSession()
      ..applyMove(parseXiangqiUciMove('h2e2'))
      ..applyMove(parseXiangqiUciMove('h9g7'))
      ..agreeDraw();
    record = BoardGameRecord.fromXiangqi(session, id: 'copy');
  }
  await BoardRecordStorage.save(record);
  return (
    page: BoardLibraryPage(game: record.game),
    copies: {
      game == 'chess' ? '复制 PGN' : '复制 ICCS 着法': game == 'chess'
          ? BoardRecordNotation.toPgn(record)
          : BoardRecordNotation.toIccs(record),
      '复制 JSON 完整备份': BoardRecordNotation.toJson(record),
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String clipboard;
  late bool denied;
  late MemoryRecordFilePicker picker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = picker = MemoryRecordFilePicker();
    clipboard = 'previous clipboard';
    denied = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => switch (call.method) {
            'Clipboard.setData' =>
              denied
                  ? throw PlatformException(code: 'denied')
                  : clipboard = (call.arguments as Map)['text'] as String,
            'Clipboard.getData' => {'text': clipboard},
            'Clipboard.hasStrings' => {'value': clipboard.isNotEmpty},
            _ => null,
          },
        );
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  Future<void> menu(WidgetTester tester, String action) async {
    await tester.tap(find.byTooltip('棋谱操作').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(action));
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  for (final game in ['go', 'gomoku', 'draughts', 'chess', 'xiangqi']) {
    testWidgets(
      '$game copies complete record formats without files or storage changes',
      (tester) async {
        final fixture = await _fixture(game);
        final prefs = await SharedPreferences.getInstance();
        Map<String, Object?> saved() => {
          for (final key in prefs.getKeys()) key: prefs.get(key),
        };
        final before = jsonEncode(saved());
        await tester.pumpWidget(MaterialApp(home: fixture.page));
        await tester.pumpAndSettle();
        for (final action in fixture.copies.entries) {
          await menu(tester, action.key);
          expect(clipboard, action.value);
          expect(find.textContaining('已复制'), findsOneWidget);
          expect(picker.savedBytes, isNull);
          expect(jsonEncode(saved()), before);
        }
        if (game == 'go') {
          expect(clipboard, contains('另一条变化'));
          expect(clipboard, contains('分享棋谱 ✓'));
        } else if (game == 'gomoku') {
          final restored = GomokuRecord.fromJson(
            jsonDecode(clipboard),
          ).restore();
          expect(restored.toJson()['actions'], hasLength(12));
          expect(restored.moves, hasLength(5));
        } else if (game == 'chess' || game == 'xiangqi') {
          final imported = BoardRecordNotation.importJson(
            clipboard,
            game == 'chess' ? BoardRecordGame.chess : BoardRecordGame.xiangqi,
          );
          expect(imported.moveCount, 2);
          expect(imported.gameOver, isTrue);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$game offers selectable text when copying is denied and remains retryable',
      (tester) async {
        final fixture = await _fixture(game);
        await tester.pumpWidget(MaterialApp(home: fixture.page));
        await tester.pumpAndSettle();
        final action = fixture.copies.entries.first;
        denied = true;
        await menu(tester, action.key);
        expect(find.text('无法自动复制'), findsOneWidget);
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const ValueKey('record-copy-fallback')),
              )
              .data,
          action.value,
        );
        expect(clipboard, 'previous clipboard');
        expect(find.textContaining('已复制'), findsNothing);
        expect(picker.savedBytes, isNull);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        denied = false;
        await menu(tester, action.key);
        expect(clipboard, action.value);
        expect(find.text('无法自动复制'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('manual copy fallback fits $size and large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      denied = true;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => copyRecordText(
                  context,
                  text: '完整棋谱\n' * 200,
                  label: 'SGF 棋谱',
                ),
                child: const Text('复制'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('record-copy-fallback')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('关闭'));
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
