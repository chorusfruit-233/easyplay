import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/chess/engine/chess_engine.dart';
import 'package:easyplay/chess/widgets/chess_board.dart';
import 'package:easyplay/chess/widgets/chess_game_page.dart';
import 'package:easyplay/chess/widgets/chess_home_page.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/records/board_record.dart';
import 'package:easyplay/records/board_record_notation.dart';
import 'package:easyplay/records/board_record_storage.dart';
import 'package:easyplay/records/record_replay.dart';
import 'package:easyplay/records/widgets/board_library_page.dart';
import 'package:easyplay/records/widgets/record_playback_page.dart';
import 'package:easyplay/xiangqi/engine/xiangqi_engine.dart';
import 'package:easyplay/xiangqi/widgets/xiangqi_board.dart';
import 'package:easyplay/xiangqi/widgets/xiangqi_game_page.dart';
import 'package:easyplay/xiangqi/widgets/xiangqi_home_page.dart';
import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_lan_connection.dart';
import '../support/record_file_picker.dart';

class _Picker extends MemoryRecordFilePicker {
  String? input;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (input == null) return null;
    final bytes = Uint8List.fromList(utf8.encode(input!));
    return FilePickerResult([
      PlatformFile(name: 'backup.json', size: bytes.length, bytes: bytes),
    ]);
  }
}

class _ChessEngine implements ChessEngine {
  final requests = <Completer<ChessMove>>[];
  @override
  Future<ChessMove> bestMove(ChessPosition position, ChessEngineLimits limits) {
    final request = Completer<ChessMove>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> start() async {}
  @override
  Future<void> newGame() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _XiangqiEngine implements XiangqiEngine {
  final requests = <Completer<XiangqiMove>>[];
  @override
  Future<XiangqiMove> bestMove(
    XiangqiPosition position,
    List<XiangqiMove> history,
    XiangqiEngineLimits limits,
  ) {
    final request = Completer<XiangqiMove>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> start() async {}
  @override
  Future<void> newGame() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

BoardGameRecord fixture(
  BoardRecordGame game, {
  bool finished = false,
  BoardRecordKind kind = BoardRecordKind.local,
}) {
  if (game == BoardRecordGame.chess) {
    final session = ChessSession()
      ..applyMove(parseUciMove('e2e4'))
      ..applyMove(parseUciMove('e7e5'));
    if (finished) session.resign(Side.white);
    return BoardGameRecord.fromChess(
      session,
      id: 'fixture',
      kind: kind,
      aiLevel: ChessAiLevel.hard,
    );
  }
  final session = XiangqiSession()
    ..applyMove(parseXiangqiUciMove('h2e2'))
    ..applyMove(parseXiangqiUciMove('h9g7'));
  if (finished) session.resign(XiangqiSide.red);
  return BoardGameRecord.fromXiangqi(
    session,
    id: 'fixture',
    kind: kind,
    aiLevel: XiangqiAiLevel.master,
  );
}

void main() {
  late _Picker picker;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = picker = _Picker();
  });

  Future<void> large(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> press(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  for (final game in BoardRecordGame.values) {
    for (final size in [const Size(320, 568), const Size(844, 390)]) {
      testWidgets('${game.name} playback controls fit $size with large text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final record = fixture(game, finished: true);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2.5)),
              child: child!,
            ),
            home: RecordPlaybackPage(
              record: game == BoardRecordGame.chess
                  ? ChessRecordReplay(record)
                  : XiangqiRecordReplay(record),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (size.width > size.height) {
          final board = find.byType(
            game == BoardRecordGame.chess ? ChessBoard : XiangqiBoard,
          );
          final paint = find.descendant(
            of: board,
            matching: find.byType(CustomPaint),
          );
          expect(tester.getSize(paint).height, greaterThan(250));
        }
        final last = find.byKey(const ValueKey('record-playback-last'));
        await tester.ensureVisible(last);
        await tester.tap(last);
        await tester.pumpAndSettle();
        expect(find.textContaining('播放完毕'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('${game.name} save errors retain the game and support retry', (
      tester,
    ) async {
      await large(tester);
      final key = BoardRecordStorage.key(game);
      SharedPreferences.setMockInitialValues({key: '{broken'});
      final record = fixture(game);
      await tester.pumpWidget(
        MaterialApp(
          home: game == BoardRecordGame.chess
              ? ChessGamePage(initialSession: record.restoreChess())
              : XiangqiGamePage(initialSession: record.restoreXiangqi()),
        ),
      );
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), '{broken');
      expect(find.text('棋谱保存失败，请重试'), findsOneWidget);
      await prefs.remove(key);
      await press(tester, '棋谱保存失败，请重试');
      expect(find.text('棋谱保存失败，请重试'), findsNothing);
      expect((await BoardRecordStorage.list(game)).single.moveCount, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      '${game.name} home opens library and resumes the same saved game',
      (tester) async {
        await large(tester);
        final record = fixture(game, kind: BoardRecordKind.ai);
        await BoardRecordStorage.save(record);
        await tester.pumpWidget(
          MaterialApp(
            home: game == BoardRecordGame.chess
                ? const ChessHomePage()
                : const XiangqiHomePage(),
          ),
        );
        await press(tester, '棋谱库');
        expect(find.byType(BoardLibraryPage), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('${game.name}-record-fixture')));
        await tester.pumpAndSettle();
        if (game == BoardRecordGame.chess) {
          final page = tester.widget<ChessGamePage>(find.byType(ChessGamePage));
          expect(page.recordId, record.id);
          expect(page.level, ChessAiLevel.hard);
          expect(page.initialSession!.moves, hasLength(2));
        } else {
          final page = tester.widget<XiangqiGamePage>(
            find.byType(XiangqiGamePage),
          );
          expect(page.recordId, record.id);
          expect(page.level, XiangqiAiLevel.master);
          expect(page.initialSession!.moves, hasLength(2));
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        final saved = await BoardRecordStorage.list(game);
        expect(saved, hasLength(1));
        expect(saved.single.id, record.id);
        expect(saved.single.createdAt, record.createdAt);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '${game.name} finished and online records open read-only playback',
      (tester) async {
        await large(tester);
        for (final online in [false, true]) {
          final record = fixture(
            game,
            finished: !online,
            kind: online ? BoardRecordKind.online : BoardRecordKind.local,
          );
          await BoardRecordStorage.save(record);
          final prefs = await SharedPreferences.getInstance();
          final before = prefs.getString(BoardRecordStorage.key(game));
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(online),
              home: BoardLibraryPage(game: game),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('${game.name}-record-fixture')));
          await tester.pumpAndSettle();
          expect(find.byType(RecordPlaybackPage), findsOneWidget);
          if (game == BoardRecordGame.chess) {
            expect(
              tester.widget<ChessBoard>(find.byType(ChessBoard)).onCell,
              isNull,
            );
          } else {
            expect(
              tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).onCell,
              isNull,
            );
          }
          await tester.tap(find.byKey(const ValueKey('record-playback-last')));
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(prefs.getString(BoardRecordStorage.key(game)), before);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets(
      '${game.name} exports notation and JSON, imports safely and confirms deletion',
      (tester) async {
        await large(tester);
        final record = fixture(game);
        await BoardRecordStorage.save(record);
        await tester.pumpWidget(
          MaterialApp(home: BoardLibraryPage(game: game)),
        );
        await tester.pumpAndSettle();
        Future<void> menu(String action) async {
          await tester.tap(find.byTooltip('棋谱操作').first);
          await tester.pumpAndSettle();
          await press(tester, action);
        }

        await menu(game == BoardRecordGame.chess ? '导出 PGN' : '导出 ICCS 着法');
        expect(
          picker.savedFileName,
          endsWith(game == BoardRecordGame.chess ? '.pgn' : '.txt'),
        );
        expect(
          utf8.decode(picker.savedBytes!),
          contains(game == BoardRecordGame.chess ? '1. e4 e5 *' : 'H2-E2'),
        );
        await menu('导出 JSON 完整备份');
        expect(jsonDecode(utf8.decode(picker.savedBytes!)), record.toJson());
        await tester.tap(find.byTooltip('导入 JSON 完整备份'));
        await tester.pumpAndSettle();
        expect(await BoardRecordStorage.list(game), hasLength(1));
        picker.input = '{}';
        await tester.tap(find.byTooltip('导入 JSON 完整备份'));
        await tester.pumpAndSettle();
        expect(find.textContaining('导入失败'), findsOneWidget);
        expect(await BoardRecordStorage.list(game), hasLength(1));
        picker.input = BoardRecordNotation.toJson(record);
        await tester.tap(find.byTooltip('导入 JSON 完整备份'));
        await tester.pumpAndSettle();
        final imported = await BoardRecordStorage.list(game);
        expect(imported, hasLength(2));
        expect(imported.map((r) => r.id).toSet(), hasLength(2));
        expect(imported.first.moveCount, 2);
        await menu('删除棋谱');
        await press(tester, '取消');
        expect(await BoardRecordStorage.list(game), hasLength(2));
        await menu('删除棋谱');
        await press(tester, '删除');
        expect(await BoardRecordStorage.list(game), hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '${game.name} auto-saves moves, undo and separate restarted games',
      (tester) async {
        await large(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: game == BoardRecordGame.chess
                ? const ChessGamePage()
                : const XiangqiGamePage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(await BoardRecordStorage.list(game), isEmpty);
        Future<void> move() async {
          if (game == BoardRecordGame.chess) {
            await tester.tap(find.byKey(const ValueKey('square-e2')));
            await tester.pump();
            await tester.tap(find.byKey(const ValueKey('square-e4')));
          } else {
            var board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
            board.onCell!(parseXiangqiSquare('h2'));
            await tester.pump();
            board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
            board.onCell!(parseXiangqiSquare('e2'));
          }
          await tester.pumpAndSettle();
        }

        await move();
        final original = (await BoardRecordStorage.list(game)).single;
        expect(original.moveCount, 1);
        await press(tester, '悔棋');
        expect((await BoardRecordStorage.list(game)).single.moveCount, 0);
        await move();
        await press(tester, '重新开局');
        await press(tester, '确认');
        expect(await BoardRecordStorage.list(game), hasLength(1));
        await move();
        final records = await BoardRecordStorage.list(game);
        expect(records, hasLength(2));
        expect(records.map((r) => r.id).toSet(), hasLength(2));
        expect(records.singleWhere((r) => r.id == original.id).moveCount, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect((await BoardRecordStorage.list(game)).first.moveCount, 1);
      },
    );

    testWidgets(
      '${game.name} playback stops stale AI and resumes exactly once',
      (tester) async {
        await large(tester);
        final chessEngine = _ChessEngine(), xiangqiEngine = _XiangqiEngine();
        final chess = ChessSession()..applyMove(parseUciMove('e2e4'));
        final xiangqi = XiangqiSession()
          ..applyMove(parseXiangqiUciMove('h2e2'));
        await tester.pumpWidget(
          MaterialApp(
            home: game == BoardRecordGame.chess
                ? ChessGamePage.ai(
                    humanSide: Side.white,
                    level: ChessAiLevel.normal,
                    engine: chessEngine,
                    initialSession: chess,
                  )
                : XiangqiGamePage.ai(
                    humanSide: XiangqiSide.red,
                    level: XiangqiAiLevel.normal,
                    engine: xiangqiEngine,
                    initialSession: xiangqi,
                  ),
          ),
        );
        await tester.pump();
        int requests() => game == BoardRecordGame.chess
            ? chessEngine.requests.length
            : xiangqiEngine.requests.length;
        int moves() => game == BoardRecordGame.chess
            ? chess.moves.length
            : xiangqi.moves.length;
        void complete() {
          if (game == BoardRecordGame.chess) {
            chessEngine.requests.last.complete(parseUciMove('e7e5'));
          } else {
            xiangqiEngine.requests.last.complete(parseXiangqiUciMove('h9g7'));
          }
        }

        expect(requests(), 1);
        await tester.tap(find.byTooltip('播放棋谱'));
        await tester.pumpAndSettle();
        complete();
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(requests(), 1);
        expect(moves(), 1);
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 400));
        expect(requests(), 2);
        complete();
        await tester.pumpAndSettle();
        expect(moves(), 2);
        final record = (await BoardRecordStorage.list(game)).single;
        expect(record.kind, BoardRecordKind.ai);
        expect(record.moveCount, 2);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '${game.name} LAN saves confirmed moves and keeps rematches separate',
      (tester) async {
        await large(tester);
        final connection = game == BoardRecordGame.chess
            ? FakeLanConnection.chess(Side.white)
            : FakeLanConnection.xiangqi(Side.white);
        await tester.pumpWidget(
          MaterialApp(
            home: game == BoardRecordGame.chess
                ? ChessGamePage.online(connection: connection)
                : XiangqiGamePage.online(connection: connection),
          ),
        );
        connection.commit(Side.white, LanMessageType.move, {
          'game': game.name,
          'move': game == BoardRecordGame.chess ? 'e2e4' : 'h2e2',
        });
        await tester.pumpAndSettle();
        final first = (await BoardRecordStorage.list(game)).single;
        expect(first.kind, BoardRecordKind.online);
        expect(first.moveCount, 1);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        connection.commit(Side.black, LanMessageType.move, {
          'game': game.name,
          'move': game == BoardRecordGame.chess ? 'e7e5' : 'h9g7',
        });
        await tester.pumpAndSettle();
        Object? onCell() => game == BoardRecordGame.chess
            ? tester.widget<ChessBoard>(find.byType(ChessBoard)).onCell
            : tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).onCell;
        expect(onCell(), isNull);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(onCell(), isNotNull);
        connection.commit(Side.black, LanMessageType.resign);
        await tester.pumpAndSettle();
        expect((await BoardRecordStorage.list(game)).single.gameOver, isTrue);
        connection.commit(Side.white, LanMessageType.rematchRequest);
        await tester.pumpAndSettle();
        connection.commit(Side.black, LanMessageType.rematchAccept, {
          'requestSeq': connection.seq,
        });
        await tester.pumpAndSettle();
        connection.commit(Side.white, LanMessageType.move, {
          'game': game.name,
          'move': game == BoardRecordGame.chess ? 'd2d4' : 'b2e2',
        });
        await tester.pumpAndSettle();
        final records = await BoardRecordStorage.list(game);
        expect(records, hasLength(2));
        expect(records.singleWhere((r) => r.id == first.id).gameOver, isTrue);
        expect(records.first.gameOver, isFalse);
        await tester.pumpWidget(const SizedBox());
        await connection.dispose();
      },
    );
  }
}
