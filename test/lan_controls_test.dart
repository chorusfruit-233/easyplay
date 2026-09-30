import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/chess/widgets/chess_game_page.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_lan_pages.dart';
import 'package:easyplay/lan/lan_match_page.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_lan_connection.dart';

void main() {
  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
  }

  for (final side in Side.values) {
    testWidgets(
      'Chess ${side.name} faces its own seat and can undo only its unanswered move',
      (tester) async {
        viewport(tester);
        final connection = FakeLanConnection.chess(side);
        await tester.pumpWidget(
          MaterialApp(home: ChessGamePage.online(connection: connection)),
        );
        final e1 = find.byKey(const ValueKey('square-e1'));
        final e8 = find.byKey(const ValueKey('square-e8'));
        expect(
          tester.getCenter(side == Side.white ? e1 : e8).dy,
          greaterThan(tester.getCenter(side == Side.white ? e8 : e1).dy),
        );
        expect(find.byTooltip('翻转棋盘'), findsNothing);
        final undo = find.widgetWithText(OutlinedButton, '悔棋');
        expect(tester.widget<OutlinedButton>(undo).onPressed, isNull);
        if (side == Side.black) {
          connection.commit(Side.white, LanMessageType.move, {'move': 'e2e4'});
          await tester.pump();
        }
        final move = side == Side.white ? 'e2e4' : 'e7e5';
        await tester.tap(
          find.byKey(ValueKey('square-${move.substring(0, 2)}')),
        );
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('square-${move.substring(2)}')));
        await tester.pumpAndSettle();
        expect(connection.sent.last.body['move'], move);
        expect(tester.widget<OutlinedButton>(undo).onPressed, isNotNull);
        connection.commit(side.opponent, LanMessageType.move, {
          'move': side == Side.white ? 'e7e5' : 'g1f3',
        });
        await tester.pumpAndSettle();
        expect(tester.widget<OutlinedButton>(undo).onPressed, isNull);
        await tester.pumpWidget(const SizedBox());
        await connection.dispose();
      },
    );
  }

  // Keep persisted Checkers interactions in one fake-clock zone: its shared
  // write queue must not outlive the clock that created its futures.
  testWidgets(
    'all Checkers variants: both perspectives, own undo and rematch storage',
    (tester) async {
      viewport(tester);
      for (final variant in DraughtsVariant.values) {
        for (final side in Side.values) {
          final connection = FakeLanConnection.draughts(variant, side);
          await tester.pumpWidget(
            MaterialApp(
              home: DraughtsLanMatchPage(
                variant: variant,
                connection: connection,
              ),
            ),
          );
          final size = DraughtsRules.forVariant(variant).boardSize;
          final top = find.byKey(const ValueKey('draughts-square-0-0'));
          final bottom = find.byKey(
            ValueKey('draughts-square-${size - 1}-${size - 1}'),
          );
          expect(
            tester.getCenter(side == Side.black ? top : bottom).dy,
            greaterThan(tester.getCenter(side == Side.black ? bottom : top).dy),
          );
          final undo = find.widgetWithText(OutlinedButton, '请求悔棋');
          expect(tester.widget<OutlinedButton>(undo).onPressed, isNull);
          Map<String, Object?> next() => {
            'path': connection.draughtsReplica!.session
                .legalMoves()
                .first
                .path
                .map((cell) => [cell.row, cell.col])
                .toList(),
          };
          if (connection.draughtsReplica!.session.turn != side) {
            connection.commit(side.opponent, LanMessageType.move, next());
            await tester.pumpAndSettle();
          }
          final move = connection.draughtsReplica!.session.legalMoves().first;
          for (final cell in move.path) {
            await tester.tap(
              find.byKey(ValueKey('draughts-square-${cell.row}-${cell.col}')),
            );
            await tester.pumpAndSettle();
          }
          expect(
            connection.sent.last.body['path'],
            move.path.map((cell) => [cell.row, cell.col]).toList(),
          );
          expect(tester.widget<OutlinedButton>(undo).onPressed, isNotNull);
          connection.commit(side.opponent, LanMessageType.move, next());
          await tester.pumpAndSettle();
          expect(tester.widget<OutlinedButton>(undo).onPressed, isNull);
          final saved = DraughtsStorage.list();
          await tester.pumpAndSettle();
          await saved;
          await tester.pumpWidget(const SizedBox());
          await connection.dispose();
        }
      }
      SharedPreferences.setMockInitialValues({});
      await rematch(tester, 'draughts');
    },
  );

  for (final game in ['go', 'chess']) {
    testWidgets(
      '$game: rematch request, rejection and acceptance reset the board',
      (tester) async {
        viewport(tester);
        await rematch(tester, game);
      },
    );
  }
}

Future<void> rematch(WidgetTester tester, String game) async {
  final connection = switch (game) {
    'chess' => FakeLanConnection.chess(Side.black),
    'draughts' => FakeLanConnection.draughts(
      DraughtsVariant.english,
      Side.black,
    ),
    _ => FakeLanConnection.go(Side.black),
  };
  final page = switch (game) {
    'chess' => ChessGamePage.online(connection: connection),
    'draughts' => DraughtsLanMatchPage(
      variant: DraughtsVariant.english,
      connection: connection,
    ),
    _ => LanMatchPage(connection: connection),
  };
  await tester.pumpWidget(MaterialApp(home: page));
  expect(find.text('再来一局'), findsNothing);
  connection.commit(Side.black, LanMessageType.resign);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('再来一局'));
  await tester.tap(find.text('再来一局'));
  await tester.pumpAndSettle();
  expect(find.text('等待对方同意再来一局…'), findsOneWidget);
  connection.commit(Side.white, LanMessageType.rematchReject, {
    'requestSeq': connection.seq,
  });
  await tester.pumpAndSettle();
  expect(find.text('再来一局'), findsOneWidget);
  connection.commit(Side.white, LanMessageType.rematchRequest);
  await tester.pumpAndSettle();
  expect(find.text('对方邀请你再来一局'), findsOneWidget);
  await tester.ensureVisible(find.text('同意'));
  await tester.tap(find.text('同意'));
  await tester.pumpAndSettle();
  expect(connection.sent.last.type, LanMessageType.rematchAccept);
  expect(find.text('再来一局'), findsNothing);
  expect(connection.authority.gameOver, isFalse);
  if (game == 'draughts') {
    final saved = DraughtsStorage.list();
    await tester.pumpAndSettle();
    final records = await saved;
    expect(records, hasLength(2));
    expect(records.map((r) => r.id).toSet(), hasLength(2));
    expect(records.where((r) => r.result != null), hasLength(1));
  }
  await tester.pumpWidget(const SizedBox());
  await connection.dispose();
}
