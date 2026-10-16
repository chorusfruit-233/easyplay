import 'package:easyplay/board.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_placement.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/chess/widgets/chess_board.dart';
import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_board.dart';
import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:easyplay/xiangqi/widgets/xiangqi_board.dart';
import 'package:easyplay/widgets/board_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The public motion scene is shared by the concrete painters. Inspect its
// rendered frames as well as the rules state, not only a controller's clock.
BoardMotionScene<T> _scene<T extends Object>(WidgetTester tester, Type board) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: find.byType(board), matching: find.byType(CustomPaint)),
  );
  return (paint.painter as dynamic).motion as BoardMotionScene<T>;
}

Future<void> _show(WidgetTester tester, Widget board) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: board)),
    ),
  ),
);

void main() {
  for (final action in ['move', 'undo', 'reset', 'replacement']) {
    testWidgets('Go clears confirmation previews after $action', (
      tester,
    ) async {
      var session = GameSession(
        GameType.go,
        goConfig: const GoConfig(boardSize: 9),
      )..placeGo(const Cell(0, 0));
      final committed = <Cell>[];
      Future<void> render() => _show(
        tester,
        Board(
          type: GameType.go,
          session: session,
          selected: null,
          targets: const [],
          placementMode: GoPlacementMode.doubleTap,
          onCell: committed.add,
        ),
      );
      BoardPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(Board),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as BoardPainter;
      await render();
      final point = tester.getCenter(find.byType(Board));
      await tester.tapAt(point);
      await render();
      expect(painter().preview, const Cell(4, 4));
      switch (action) {
        case 'move':
          expect(session.placeGo(const Cell(0, 1)), isTrue);
        case 'undo':
          expect(session.undo(), isTrue);
        case 'reset':
          session.reset();
        case 'replacement':
          session = GameSession(
            GameType.go,
            goConfig: const GoConfig(boardSize: 9),
          )..placeGo(const Cell(0, 0));
      }
      await render();
      expect(painter().preview, isNull);
      await tester.tapAt(point);
      await render();
      expect(committed, isEmpty, reason: 'The old preview must not confirm');
      expect(painter().preview, const Cell(4, 4));
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'Go and Gomoku commit fast taps without waiting for landing animation',
    (tester) async {
      final go = GameSession(
        GameType.go,
        goConfig: const GoConfig(boardSize: 9),
      );
      Future<void> renderGo() => _show(
        tester,
        Board(
          type: GameType.go,
          session: go,
          selected: null,
          targets: const [],
          onCell: (cell) => go.placeGo(cell),
        ),
      );
      await renderGo();
      expect(go.placeGo(const Cell(4, 4)), isTrue);
      await renderGo();
      expect(_scene<GamePiece>(tester, Board).isAnimating, isTrue);
      final rect = tester.getRect(find.byType(Board));
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * 5.5 / 9, rect.height * 4.5 / 9),
      );
      expect(go.moves.length, 2);
      await renderGo();
      await tester.pumpAndSettle();
      expect(_scene<GamePiece>(tester, Board).frames.length, 2);

      final gomoku = GomokuSession();
      Future<void> renderGomoku() => _show(
        tester,
        GomokuBoard(
          session: gomoku,
          onCell: (cell) => gomoku.place(cell),
          placementMode: GoPlacementMode.direct,
        ),
      );
      await renderGomoku();
      expect(gomoku.place(const Cell(7, 7)), isTrue);
      await renderGomoku();
      expect(_scene<Side>(tester, GomokuBoard).isAnimating, isTrue);
      final bounds = tester.getRect(find.byType(GomokuBoard));
      await tester.tapAt(
        bounds.topLeft +
            Offset(bounds.width * 8.5 / 15, bounds.height * 7.5 / 15),
      );
      expect(gomoku.moves.length, 2);
      await renderGomoku();
      await tester.pumpAndSettle();
      expect(_scene<Side>(tester, GomokuBoard).frames.length, 2);
    },
  );

  testWidgets('castling animates both king and rook in either orientation', (
    tester,
  ) async {
    for (final flipped in [false, true]) {
      final session = ChessSession(
        position: parseFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'),
      );
      Future<void> render() => _show(
        tester,
        ChessBoard(session: session, onCell: null, flipped: flipped),
      );
      await tester.pumpWidget(const SizedBox());
      await render();
      expect(session.applyMove(parseUciMove('e1g1')), isTrue);
      await render();
      final scene = _scene<ChessPiece>(tester, ChessBoard);
      expect(
        scene.frames.where((p) => p.moving).map((p) => p.piece.type).toSet(),
        {ChessPieceType.king, ChessPieceType.rook},
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        scene.frames
            .singleWhere((p) => p.moving && p.piece.type == ChessPieceType.king)
            .position
            .dx,
        closeTo(5, .1),
      );
      await tester.pumpAndSettle();
      expect(
        session.position.pieceAt(parseChessSquare('g1'))!.type,
        ChessPieceType.king,
      );
      expect(
        session.position.pieceAt(parseChessSquare('f1'))!.type,
        ChessPieceType.rook,
      );
      expect(scene.frames.where((p) => p.departing || p.moving), isEmpty);
    }
  });

  testWidgets('en passant fades the captured pawn on its actual square', (
    tester,
  ) async {
    final session = ChessSession(
      position: parseFen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1'),
    );
    Future<void> render() =>
        _show(tester, ChessBoard(session: session, onCell: null));
    await render();
    expect(session.applyMove(parseUciMove('e5d6')), isTrue);
    await render();
    final scene = _scene<ChessPiece>(tester, ChessBoard);
    expect(
      scene.frames.singleWhere((p) => p.departing).destination,
      parseChessSquare('d5'),
    );
    await tester.pumpAndSettle();
    expect(
      scene.frames
          .where((p) => p.piece.type == ChessPieceType.pawn)
          .single
          .destination,
      parseChessSquare('d6'),
    );
  });

  testWidgets('promotion travels as the pawn and settles as the chosen piece', (
    tester,
  ) async {
    final session = ChessSession(
      position: parseFen('4k3/P7/8/8/8/8/8/4K3 w - - 0 1'),
    );
    Future<void> render() =>
        _show(tester, ChessBoard(session: session, onCell: null));
    await render();
    expect(session.applyMove(parseUciMove('a7a8q')), isTrue);
    await render();
    final scene = _scene<ChessPiece>(tester, ChessBoard);
    expect(
      scene.frames.singleWhere((p) => p.moving).piece.type,
      ChessPieceType.pawn,
    );
    await tester.pumpAndSettle();
    expect(
      scene.frames
          .singleWhere((p) => p.destination == parseChessSquare('a8'))
          .piece
          .type,
      ChessPieceType.queen,
    );
  });

  testWidgets('Xiangqi capture and immediate undo restore every piece', (
    tester,
  ) async {
    final session = XiangqiSession();
    Future<void> render() => _show(tester, XiangqiBoard(session: session));
    await render();
    expect(session.applyMove(parseXiangqiUciMove('b2b9')), isTrue);
    await render();
    final scene = _scene<XiangqiPiece>(tester, XiangqiBoard);
    expect(
      scene.frames.singleWhere((p) => p.moving).piece.type,
      XiangqiPieceType.cannon,
    );
    expect(
      scene.frames.singleWhere((p) => p.departing).piece.type,
      XiangqiPieceType.horse,
    );
    expect(session.undo(), isTrue);
    await render();
    expect(scene.isAnimating, isFalse);
    expect(scene.frames.length, 32);
    expect(scene.frames.where((p) => p.moving || p.departing), isEmpty);
  });

  testWidgets(
    'draughts traverses every landing and fades captures after crossing them',
    (tester) async {
      final cells = <Cell, DraughtsPiece>{
        const Cell(0, 1): const DraughtsPiece(Side.black),
        const Cell(1, 2): const DraughtsPiece(Side.white),
        const Cell(3, 4): const DraughtsPiece(Side.white),
        const Cell(5, 6): const DraughtsPiece(Side.white),
        const Cell(7, 0): const DraughtsPiece(Side.white),
      };
      final position = DraughtsPosition(8, [
        for (var r = 0; r < 8; r++)
          for (var c = 0; c < 8; c++) cells[Cell(r, c)],
      ]);
      final session = DraughtsSession(
        DraughtsRules.forVariant(DraughtsVariant.english),
        position: position,
        turn: Side.black,
      );
      Cell? tapped;
      Future<void> render() => _show(
        tester,
        DraughtsBoard(session: session, onCell: (cell) => tapped = cell),
      );
      await render();
      expect(session.applyMove(session.legalMoves().single), isTrue);
      await render();
      final animated = tester
          .widgetList<AnimatedBuilder>(
            find.descendant(
              of: find.byType(DraughtsBoard),
              matching: find.byType(AnimatedBuilder),
            ),
          )
          .singleWhere(
            (widget) => widget.animation is BoardMotionScene<DraughtsPiece>,
          );
      final scene = animated.animation as BoardMotionScene<DraughtsPiece>;
      expect(scene.frames.where((p) => p.departing).length, 3);
      await tester.pump(const Duration(milliseconds: 140));
      expect(
        scene.frames.singleWhere((p) => p.moving).position,
        const Offset(3, 2),
      );
      expect(
        scene.frames
            .singleWhere(
              (p) => p.departing && p.destination == const Cell(1, 2),
            )
            .opacity,
        lessThan(1),
      );
      expect(
        scene.frames.where((p) => p.departing && p.opacity == 1).length,
        2,
      );
      await tester.tap(find.byKey(const ValueKey('draughts-square-7-0')));
      expect(tapped, const Cell(7, 0));
      await tester.pumpAndSettle();
      expect(scene.frames.length, 2);
      expect(
        scene.frames.singleWhere((p) => p.piece.side == Side.black).destination,
        const Cell(6, 7),
      );
    },
  );
}
