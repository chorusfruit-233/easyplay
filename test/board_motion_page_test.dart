import 'package:easyplay/gomoku/gomoku_variant.dart';
import 'package:easyplay/board.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_board.dart';
import 'package:easyplay/draughts/widgets/draughts_game_page.dart';
import 'package:easyplay/draughts/widgets/draughts_lan_pages.dart';
import 'package:easyplay/game_session.dart' show Cell, Side, GamePiece;
import 'package:easyplay/go_placement.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/gomoku/widgets/gomoku_lan_pages.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/lan_match_page.dart';
import 'package:easyplay/widgets/board_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_lan_connection.dart';

BoardMotionScene<DraughtsPiece> _draughtsScene(WidgetTester tester) => tester
    .widgetList<AnimatedBuilder>(
      find.descendant(
        of: find.byType(DraughtsBoard),
        matching: find.byType(AnimatedBuilder),
      ),
    )
    .map((widget) => widget.animation)
    .whereType<BoardMotionScene<DraughtsPiece>>()
    .single;

BoardMotionScene<Side> _gomokuScene(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(GomokuBoard),
      matching: find.byType(CustomPaint),
    ),
  );
  return (paint.painter as dynamic).motion as BoardMotionScene<Side>;
}

BoardMotionScene<GamePiece> _goScene(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: find.byType(Board), matching: find.byType(CustomPaint)),
  );
  return (paint.painter as dynamic).motion as BoardMotionScene<GamePiece>;
}

Future<void> _playDraughts(WidgetTester tester, DraughtsMove move) async {
  for (final cell in move.path) {
    await tester.tap(
      find.byKey(ValueKey('draughts-square-${cell.row}-${cell.col}')),
    );
    await tester.pump();
  }
}

Future<void> _expectDraughtsMotion(
  WidgetTester tester,
  DraughtsMove move,
) async {
  final scene = _draughtsScene(tester);
  expect(scene.isAnimating, isTrue);
  await tester.pump(const Duration(milliseconds: 120));
  final frame = scene.frames.singleWhere((frame) => frame.moving);
  expect(
    frame.position,
    isNot(Offset(move.from.col.toDouble(), move.from.row.toDouble())),
  );
  expect(
    frame.position,
    isNot(Offset(move.to.col.toDouble(), move.to.row.toDouble())),
  );
  await tester.pumpAndSettle();
  expect(
    scene.frames.where((frame) => frame.moving || frame.departing),
    isEmpty,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      GoPlacementPreferences.key: GoPlacementMode.direct.name,
    });
  });

  testWidgets('local draughts page shows intermediate frames and undo snaps', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
    );
    await tester.pumpWidget(
      MaterialApp(home: DraughtsGamePage(session: session)),
    );
    await tester.pumpAndSettle();
    final move = session.legalMoves().first;
    await _playDraughts(tester, move);
    expect(session.moves, [move]);
    await _expectDraughtsMotion(tester, move);
    await tester.tap(find.text('悔棋'));
    await tester.pumpAndSettle();
    expect(session.moves, isEmpty);
    expect(_draughtsScene(tester).isAnimating, isFalse);
    expect(_draughtsScene(tester).frames, hasLength(24));
  });

  testWidgets('LAN draughts animates both a local move and the remote reply', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final connection = FakeLanConnection.draughts(
      DraughtsVariant.english,
      Side.black,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DraughtsLanMatchPage(
          connection: connection,
          variant: DraughtsVariant.english,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final move = connection.draughtsReplica!.session.legalMoves().first;
    await _playDraughts(tester, move);
    expect(connection.sent.single.type, LanMessageType.move);
    await _expectDraughtsMotion(tester, move);
    final reply = connection.draughtsReplica!.session.legalMoves().first;
    connection.commit(Side.white, LanMessageType.move, reply.toJson());
    await tester.pump();
    await tester.pump();
    await _expectDraughtsMotion(tester, reply);
    expect(connection.draughtsReplica!.session.moves, [move, reply]);
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });

  testWidgets('LAN Gomoku animates local and remote stones, then undo snaps', (
    tester,
  ) async {
    final connection = FakeLanConnection.gomoku(
      Side.black,
      variant: GomokuVariant.freestyle,
    );
    await tester.pumpWidget(
      MaterialApp(home: GomokuLanMatchPage(connection: connection)),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(GomokuBoard)));
    await tester.pump();
    expect(connection.sent.single.type, LanMessageType.move);
    var scene = _gomokuScene(tester);
    expect(scene.isAnimating, isTrue);
    expect(scene.frames.single.scale, lessThan(1));
    await tester.pumpAndSettle();
    connection.commit(Side.white, LanMessageType.move, {
      'cell': [7, 8],
    });
    await tester.pump();
    await tester.pump();
    scene = _gomokuScene(tester);
    expect(scene.isAnimating, isTrue);
    final initial = scene.frames.singleWhere(
      (f) => f.destination == const Cell(7, 8),
    );
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      scene.frames.singleWhere((f) => f.destination == const Cell(7, 8)).scale,
      greaterThan(initial.scale),
    );
    connection.commit(Side.white, LanMessageType.undoRequest);
    await tester.pumpAndSettle();
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();
    expect(connection.gomokuReplica!.session.moves, hasLength(1));
    expect(_gomokuScene(tester).isAnimating, isFalse);
    expect(_gomokuScene(tester).frames, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });

  testWidgets('LAN Go animates both a local stone and the remote reply', (
    tester,
  ) async {
    final connection = FakeLanConnection.go(Side.black);
    await tester.pumpWidget(
      MaterialApp(home: LanMatchPage(connection: connection)),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(Board)));
    await tester.pump();
    expect(connection.sent.single.type, LanMessageType.move);
    expect(_goScene(tester).isAnimating, isTrue);
    expect(_goScene(tester).frames.single.scale, lessThan(1));
    await tester.pumpAndSettle();
    connection.commit(Side.white, LanMessageType.move, {
      'cell': [4, 5],
    });
    await tester.pump();
    await tester.pump();
    final scene = _goScene(tester);
    expect(scene.isAnimating, isTrue);
    final initial = scene.frames.singleWhere(
      (f) => f.destination == const Cell(4, 5),
    );
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      scene.frames.singleWhere((f) => f.destination == const Cell(4, 5)).scale,
      greaterThan(initial.scale),
    );
    await tester.pumpAndSettle();
    expect(scene.frames, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await connection.dispose();
  });
}
