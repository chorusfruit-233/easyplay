import 'dart:async';

import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/gomoku/widgets/gomoku_game_page.dart';
import 'package:easyplay/gomoku/widgets/gomoku_home_page.dart';
import 'package:easyplay/gomoku/widgets/gomoku_lan_pages.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_lan_connection.dart';

class _DecisionAi extends GomokuAi {
  final requests = <Completer<GomokuAction?>>[];
  final positions = <GomokuSession>[];
  @override
  Future<GomokuAction?> decide(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
  }) {
    positions.add(source.fork());
    final request = Completer<GomokuAction?>();
    requests.add(request);
    return request.future;
  }

  @override
  void cancel() {}
}

Future<void> tapCell(
  WidgetTester tester,
  Cell cell, {
  bool confirm = true,
}) async {
  final rect = tester.getRect(find.byType(GomokuBoard));
  final point =
      rect.topLeft +
      Offset(
        (cell.col + .5) * rect.width / 15,
        (cell.row + .5) * rect.height / 15,
      );
  await tester.tapAt(point);
  await tester.pump();
  if (confirm) {
    await tester.tapAt(point);
    await tester.pump();
  }
}

Future<void> button(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final exchange in [false, true]) {
    testWidgets(
      'local exchange=$exchange: default preview through all opening stages',
      (tester) async {
        final session = GomokuSession();
        await tester.pumpWidget(
          MaterialApp(home: GomokuGamePage(session: session)),
        );
        await tester.pumpAndSettle();
        for (final cell in [
          const Cell(7, 7),
          const Cell(6, 7),
          const Cell(6, 6),
        ]) {
          final count = session.moves.length;
          await tapCell(tester, cell, confirm: false);
          expect(session.moves, hasLength(count));
          expect((await GomokuStorage.list()).single.moveCount, count);
          await tapCell(tester, cell, confirm: false);
          expect(session.moves, hasLength(count + 1));
        }
        expect(
          tester.widget<GomokuBoard>(find.byType(GomokuBoard)).enabled,
          isFalse,
        );
        await button(tester, exchange ? '交换执棋' : '不交换');
        expect(session.exchanged, exchange);
        await tapCell(tester, const Cell(8, 8));
        await tapCell(tester, const Cell(8, 7));
        await tapCell(tester, const Cell(7, 8));
        expect(session.proposals, hasLength(2));
        expect(session.moves, hasLength(4));
        expect((await GomokuStorage.list()).single.moveCount, 4);
        await tapCell(tester, const Cell(7, 8), confirm: false);
        expect(session.moves, hasLength(4));
        await tapCell(tester, const Cell(7, 8), confirm: false);
        expect(session.moves, hasLength(5));
        expect(session.pieceAt(const Cell(8, 7)), isNull);
        await tapCell(tester, const Cell(8, 7));
        expect(session.pieceAt(const Cell(8, 7)), Side.white);
        expect(
          (await GomokuStorage.list()).single.restore().toJson(),
          session.toJson(),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'AI swaps, proposes twice and hands selection and W6 to the same human',
    (tester) async {
      final session = GomokuSession(), ai = _DecisionAi();
      await tester.pumpWidget(
        MaterialApp(
          home: GomokuGamePage(
            session: session,
            ai: ai,
            aiLevel: GomokuAiLevel.beginner,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final cell in [
        const Cell(7, 7),
        const Cell(6, 7),
        const Cell(6, 6),
      ]) {
        await tapCell(tester, cell);
      }
      expect(ai.requests, hasLength(1));
      expect(ai.positions.last.phase, GomokuPhase.exchange);
      ai.requests.last.complete(const GomokuAction.exchange(true));
      await tester.pumpAndSettle();
      expect(find.textContaining('你执白方（已交换）'), findsOneWidget);
      await tapCell(tester, const Cell(8, 8));
      expect(ai.positions.last.phase, GomokuPhase.proposals);
      ai.requests.last.complete(const GomokuAction.place(Cell(8, 7)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(ai.positions.last.proposals, [const Cell(8, 7)]);
      ai.requests.last.complete(const GomokuAction.place(Cell(7, 8)));
      await tester.pumpAndSettle();
      expect(session.moves, hasLength(4));
      expect(session.actor, Side.black);
      await tapCell(tester, const Cell(7, 8));
      expect(session.moves, hasLength(5));
      expect(ai.requests, hasLength(3));
      await tapCell(tester, const Cell(8, 7));
      expect(session.moves, hasLength(6));
      expect(ai.requests, hasLength(4));
      expect(ai.positions.last.turn, Side.black);
      await tester.pumpWidget(const SizedBox());
      ai.requests.last.complete(null);
      await tester.pump();
    },
  );

  testWidgets(
    'background cancels exchange decision and rejects the stale AI choice',
    (tester) async {
      final session = GomokuSession()
        ..place(const Cell(7, 7))
        ..place(const Cell(6, 7))
        ..place(const Cell(6, 6));
      final ai = _DecisionAi();
      await tester.pumpWidget(
        MaterialApp(
          home: GomokuGamePage(
            session: session,
            ai: ai,
            aiLevel: GomokuAiLevel.beginner,
          ),
        ),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(ai.requests, hasLength(2));
      ai.requests.first.complete(const GomokuAction.exchange(true));
      await tester.pump();
      expect(session.phase, GomokuPhase.exchange);
      ai.requests.last.complete(const GomokuAction.exchange(false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(session.exchanged, isFalse);
      expect(session.phase, GomokuPhase.fourth);
      // AI also owns W4 when it keeps white.
      expect(ai.requests, hasLength(3));
      await tester.pumpWidget(const SizedBox());
      ai.requests.last.complete(null);
      await tester.pump();
    },
  );

  testWidgets(
    'LAN swap preserves authenticated seat while moving white and selecting black5',
    (tester) async {
      final connection = FakeLanConnection.gomoku(Side.black);
      await tester.pumpWidget(
        MaterialApp(home: GomokuLanMatchPage(connection: connection)),
      );
      await tester.pumpAndSettle();
      for (final cell in [
        const Cell(7, 7),
        const Cell(6, 7),
        const Cell(6, 6),
      ]) {
        await tapCell(tester, cell);
        await tester.pumpAndSettle();
      }
      connection.commit(Side.white, LanMessageType.gomokuExchange, {
        'exchange': true,
      });
      await tester.pumpAndSettle();
      expect(find.text('轮到你 · 白方'), findsOneWidget);
      await tapCell(tester, const Cell(8, 8));
      await tester.pumpAndSettle();
      expect(connection.sent.last.body['side'], 'B');
      for (final cell in [
        [8, 7],
        [7, 8],
      ]) {
        connection.commit(Side.white, LanMessageType.move, {'cell': cell});
        await tester.pumpAndSettle();
      }
      expect(connection.gomokuReplica!.session.moves, hasLength(4));
      await tapCell(tester, const Cell(7, 8));
      await tester.pumpAndSettle();
      expect(connection.sent.last.body['side'], 'B');
      expect(
        connection.gomokuReplica!.session.pieceAt(const Cell(7, 8)),
        Side.black,
      );
      await tapCell(tester, const Cell(8, 7));
      await tester.pumpAndSettle();
      expect(
        connection.gomokuReplica!.session.pieceAt(const Cell(8, 7)),
        Side.white,
      );
      await tester.pumpWidget(const SizedBox());
      await connection.dispose();
    },
  );

  testWidgets(
    'legacy entertainment records open read-only without changing saved data',
    (tester) async {
      final session = GomokuSession(variant: GomokuVariant.freestyle)
        ..place(const Cell(7, 7));
      await GomokuStorage.save(
        GomokuRecord(
          id: 'legacy',
          createdAt: DateTime.utc(2026),
          session: session,
        ),
      );
      final before = (await GomokuStorage.list()).single.toJson();
      await tester.pumpWidget(const MaterialApp(home: GomokuHomePage()));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<GomokuVariant>), findsNothing);
      await tester.scrollUntilVisible(find.text('自由五子棋 · 1 手'), 200);
      await tester.tap(find.text('自由五子棋 · 1 手'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GomokuBoard>(find.byType(GomokuBoard)).enabled,
        isFalse,
      );
      expect(find.text('旧规则存档 · 仅供查看'), findsOneWidget);
      expect(find.text('重开'), findsNothing);
      expect(find.text('悔棋'), findsNothing);
      await tapCell(tester, const Cell(8, 8));
      expect((await GomokuStorage.list()).single.toJson(), before);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
