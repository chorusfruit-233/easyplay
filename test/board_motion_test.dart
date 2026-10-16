import 'package:easyplay/game_session.dart';
import 'package:easyplay/widgets/board_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Painter extends CustomPainter {
  _Painter(this.scene) : super(repaint: scene);
  final BoardMotionScene<String> scene;
  @override
  void paint(Canvas canvas, Size size) => scene.paint(
    canvas,
    center: (at) => Offset((at.dx + .5) * 30, (at.dy + .5) * 30),
    piecePainter: (canvas, _) => canvas.drawCircle(Offset.zero, 12, Paint()),
  );
  @override
  bool shouldRepaint(covariant _Painter oldDelegate) => true;
}

Future<BoardMotionScene<String>> _show(
  WidgetTester tester, {
  required Map<Cell, String> pieces,
  List<Object> history = const [],
  BoardMoveMotion? move,
  Object configuration = 0,
  bool reduced = false,
  bool tickers = true,
}) async {
  late BoardMotionScene<String> scene;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: tickers,
          child: AnimatedBoard<String>(
            pieces: pieces,
            history: history,
            pieceKey: (p) => p,
            configuration: configuration,
            move: move,
            builder: (_, value) {
              scene = value;
              return CustomPaint(painter: _Painter(value));
            },
          ),
        ),
      ),
    ),
  );
  return scene;
}

void main() {
  const a = Cell(1, 1), b = Cell(1, 3), c = Cell(3, 3);
  final step = BoardMoveMotion(
    paths: [
      [a, b],
    ],
  );

  test('motion takes immutable snapshots of paths and capture times', () {
    final path = [a, b];
    final paths = [path];
    final captureAt = {c: .5};
    final motion = BoardMoveMotion(paths: paths, captureAt: captureAt);

    path[0] = c;
    paths.clear();
    captureAt[c] = .9;
    expect(motion.paths, [
      [a, b],
    ]);
    expect(motion.captureAt, {c: .5});
    expect(() => motion.paths.add([c]), throwsUnsupportedError);
    expect(() => motion.paths[0] = [c], throwsUnsupportedError);
    expect(() => motion.paths.single.add(c), throwsUnsupportedError);
    expect(() => motion.captureAt[c] = 0, throwsUnsupportedError);
  });

  test('motion permits no paths, a new stone and a non-adjacent revisit', () {
    expect(BoardMoveMotion(paths: []).paths, isEmpty);
    expect(
      BoardMoveMotion(
        paths: [
          [a],
        ],
      ).paths.single,
      [a],
    );
    expect(BoardMoveMotion.alongPath([a, b, a], []).paths.single, [a, b, a]);
  });

  test('motion rejects empty paths and adjacent zero-length segments', () {
    expect(() => BoardMoveMotion(paths: [[]]), throwsArgumentError);
    expect(() => BoardMoveMotion.alongPath([], []), throwsArgumentError);
    expect(
      () => BoardMoveMotion(
        paths: [
          [a, a],
        ],
      ),
      throwsArgumentError,
    );
    expect(() => BoardMoveMotion.alongPath([a, a], [b]), throwsArgumentError);
    expect(() => BoardMoveMotion.alongPath([a, b, b], []), throwsArgumentError);
  });

  test('capture paths reject excess captures and duplicate victims', () {
    expect(() => BoardMoveMotion.alongPath([a], [b]), throwsArgumentError);
    expect(
      () => BoardMoveMotion.alongPath([a, b], [a, c]),
      throwsArgumentError,
    );
    expect(
      () => BoardMoveMotion.alongPath([a, b, c], [b, b]),
      throwsArgumentError,
    );
  });

  test('capture times are finite and clamped to the animation interval', () {
    final motion = BoardMoveMotion(
      paths: [
        [a, b],
      ],
      captureAt: {
        const Cell(0, 0): -1,
        const Cell(0, 1): 2,
        const Cell(0, 2): double.nan,
        const Cell(0, 3): double.infinity,
        const Cell(0, 4): double.negativeInfinity,
        const Cell(0, 5): .5,
      },
    );
    expect(motion.captureAt, {
      const Cell(0, 0): 0.0,
      const Cell(0, 1): 1.0,
      const Cell(0, 2): 0.0,
      const Cell(0, 3): 0.0,
      const Cell(0, 4): 0.0,
      const Cell(0, 5): .5,
    });
  });

  testWidgets('endpoint captures remain visible until the settled board', (
    tester,
  ) async {
    final scene = await _show(tester, pieces: {a: 'white', c: 'black'});
    await _show(
      tester,
      pieces: {b: 'white'},
      history: [1],
      move: BoardMoveMotion(
        paths: [
          [a, b],
        ],
        captureAt: {c: 1},
      ),
    );
    expect(scene.frames.singleWhere((p) => p.departing).opacity, 1);
    await tester.pump(const Duration(milliseconds: 239));
    expect(scene.isAnimating, isTrue);
    final captured = scene.frames.singleWhere((p) => p.departing);
    expect(captured.opacity, 1);
    expect(captured.scale, 1);
    await tester.pumpAndSettle();
    expect(scene.frames.single.piece, 'white');
    expect(scene.frames.single.position, const Offset(3, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'flying king capture fades when crossed rather than at the jump midpoint',
    (tester) async {
      const start = Cell(0, 0), captured = Cell(0, 1), end = Cell(0, 7);
      final scene = await _show(
        tester,
        pieces: {start: 'king', captured: 'enemy'},
      );
      await _show(
        tester,
        pieces: {end: 'king'},
        history: [1],
        move: BoardMoveMotion.alongPath([start, end], [captured]),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(scene.frames.singleWhere((p) => p.departing).opacity, 1);
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        scene.frames.singleWhere((p) => p.moving).position.dx,
        greaterThan(1),
      );
      expect(scene.frames.singleWhere((p) => p.departing).opacity, lessThan(1));
      await tester.pumpAndSettle();
      expect(scene.frames.single.destination, end);
    },
  );

  testWidgets(
    'opening a saved position is immediate; one new stone gently appears',
    (tester) async {
      final scene = await _show(tester, pieces: {a: 'black'}, history: [1]);
      expect(scene.isAnimating, isFalse);
      expect(scene.frames.single.scale, 1);
      await _show(
        tester,
        pieces: {a: 'black', b: 'white'},
        history: [1, 2],
        move: BoardMoveMotion(
          paths: [
            [b],
          ],
        ),
      );
      expect(scene.isAnimating, isTrue);
      final initial = scene.frames.singleWhere((p) => p.destination == b);
      expect(initial.scale, lessThan(1));
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        scene.frames.singleWhere((p) => p.destination == b).scale,
        greaterThan(initial.scale),
      );
      await tester.pumpAndSettle();
      expect(scene.frames.length, 2);
      expect(scene.frames.every((p) => p.scale == 1 && p.opacity == 1), isTrue);
    },
  );

  testWidgets(
    'move interpolates while captured piece fades; settled frame has no ghosts',
    (tester) async {
      final scene = await _show(tester, pieces: {a: 'white', b: 'black'});
      await _show(tester, pieces: {b: 'white'}, history: [1], move: step);
      expect(scene.frames.where((p) => p.departing).single.piece, 'black');
      await tester.pump(const Duration(milliseconds: 120));
      final moving = scene.frames.singleWhere((p) => p.moving);
      expect(moving.position.dx, closeTo(2, .1));
      expect(moving.position.dy, 1);
      await tester.pumpAndSettle();
      expect(scene.frames.single.position, const Offset(3, 1));
      expect(scene.frames.single.piece, 'white');
      expect(scene.frames.single.moving, isFalse);
    },
  );

  testWidgets(
    'rapid replies replace unfinished visuals; undo and restart snap immediately',
    (tester) async {
      final scene = await _show(tester, pieces: {a: 'white', c: 'black'});
      await _show(
        tester,
        pieces: {b: 'white', c: 'black'},
        history: [1],
        move: step,
      );
      await tester.pump(const Duration(milliseconds: 40));
      await _show(
        tester,
        pieces: {b: 'white', a: 'black'},
        history: [1, 2],
        move: BoardMoveMotion(
          paths: [
            [c, a],
          ],
        ),
      );
      expect(
        scene.frames.singleWhere((p) => p.piece == 'white').position,
        const Offset(3, 1),
      );
      expect(scene.frames.where((p) => p.moving).length, 1);
      await _show(
        tester,
        pieces: {b: 'white', c: 'black'},
        history: [1],
        move: step,
      );
      expect(scene.isAnimating, isFalse);
      expect(scene.frames.map((p) => p.destination).toSet(), {b, c});
      await _show(tester, pieces: {}, history: []);
      expect(scene.frames, isEmpty);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bulk synchronization, replacing history and flipping do not replay old moves',
    (tester) async {
      final scene = await _show(tester, pieces: {a: 'white'});
      await _show(tester, pieces: {b: 'white'}, history: [1, 2, 3], move: step);
      expect(scene.isAnimating, isFalse);
      await _show(
        tester,
        pieces: {a: 'white'},
        history: [7, 8, 9, 10],
        move: BoardMoveMotion(
          paths: [
            [b, a],
          ],
        ),
      );
      expect(scene.isAnimating, isFalse);
      await _show(
        tester,
        pieces: {b: 'white'},
        history: [7, 8, 9, 10, 11],
        move: step,
        configuration: 1,
      );
      expect(scene.isAnimating, isFalse);
    },
  );

  testWidgets(
    'reduced motion and muted tickers show the final board immediately',
    (tester) async {
      final scene = await _show(tester, pieces: {a: 'white'});
      await _show(tester, pieces: {b: 'white'}, history: [1], move: step);
      expect(scene.isAnimating, isTrue);
      await _show(
        tester,
        pieces: {b: 'white'},
        history: [1],
        move: step,
        reduced: true,
      );
      expect(scene.isAnimating, isFalse);
      expect(scene.frames.single.position, const Offset(3, 1));
      await _show(
        tester,
        pieces: {a: 'white'},
        history: [1, 2],
        move: BoardMoveMotion(
          paths: [
            [b, a],
          ],
        ),
        tickers: false,
      );
      expect(scene.isAnimating, isFalse);
      expect(scene.frames.single.position, const Offset(1, 1));
    },
  );

  testWidgets(
    'backgrounding finishes animation, accepts current state and resumes without stale playback',
    (tester) async {
      final scene = await _show(tester, pieces: {a: 'white'});
      await _show(tester, pieces: {b: 'white'}, history: [1], move: step);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(scene.isAnimating, isFalse);
      expect(scene.frames.single.position, const Offset(3, 1));
      await _show(
        tester,
        pieces: {a: 'white'},
        history: [1, 2],
        move: BoardMoveMotion(
          paths: [
            [b, a],
          ],
        ),
      );
      expect(scene.isAnimating, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(scene.frames.single.position, const Offset(1, 1));
      await _show(tester, pieces: {b: 'white'}, history: [1, 2, 3], move: step);
      expect(scene.isAnimating, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
