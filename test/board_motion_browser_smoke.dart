// Standalone visual regression target. Not included in the product build.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:web/web.dart' as web;
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

final _demo = GlobalKey<_DemoState>();
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(_Demo(key: _demo));
  final api = JSObject();
  api['game'] = ((JSString game) => _demo.currentState!.change(
    game.toDart,
  )).toJS;
  api['move'] = (() => _demo.currentState!.move()).toJS;
  api['undo'] = (() => _demo.currentState!.undo()).toJS;
  api['flip'] = (() => _demo.currentState!.flip()).toJS;
  api['slow'] = ((JSNumber factor) => timeDilation = factor.toDartDouble).toJS;
  api['state'] = (() => jsonEncode(_demo.currentState!.snapshot()).toJS).toJS;
  web.window.setProperty('easyplayBoardMotion'.toJS, api);
}

class _Demo extends StatefulWidget {
  const _Demo({super.key});
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  String game = 'go';
  Cell? lastTap;
  Map<String, double>? _boardBounds;
  Map<String, Object?>? _lastMoveTrail;
  bool reduced = false;
  bool flipped = false;
  int generation = 0, renderedGeneration = -1;
  GameSession go = GameSession(
    GameType.go,
    goConfig: const GoConfig(boardSize: 9),
  );
  GomokuSession gomoku = GomokuSession(variant: GomokuVariant.freestyle);
  ChessSession chess = ChessSession();
  XiangqiSession xiangqi = XiangqiSession();
  late DraughtsSession draughts;
  String get label => switch (game) {
    'go' => '围棋 · 轻盈落子',
    'gomoku' => '五子棋 · 落子反馈',
    'chess' => '国际象棋 · 王车易位',
    'xiangqi' => '中国象棋 · 行棋与吃子',
    _ => '跳棋 · 连跳与吃子',
  };
  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    lastTap = null;
    flipped = false;
    go = GameSession(GameType.go, goConfig: const GoConfig(boardSize: 9));
    gomoku = GomokuSession(variant: GomokuVariant.freestyle);
    chess = ChessSession(
      position: parseFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'),
    );
    xiangqi = XiangqiSession();
    final pieces = <Cell, DraughtsPiece>{
      const Cell(0, 1): const DraughtsPiece(Side.black),
      const Cell(1, 2): const DraughtsPiece(Side.white),
      const Cell(3, 4): const DraughtsPiece(Side.white),
      const Cell(5, 6): const DraughtsPiece(Side.white),
      const Cell(7, 0): const DraughtsPiece(Side.white),
    };
    draughts = DraughtsSession(
      DraughtsRules.forVariant(DraughtsVariant.english),
      position: DraughtsPosition(8, [
        for (var r = 0; r < 8; r++)
          for (var c = 0; c < 8; c++) pieces[Cell(r, c)],
      ]),
      turn: Side.black,
    );
  }

  void _mutate(VoidCallback action) => setState(() {
    generation++;
    action();
  });
  void change(String value) => _mutate(() {
    game = value;
    _reset();
  });
  void move() => _mutate(() {
    switch (game) {
      case 'go':
        go.placeGo(Cell(4, 4 + go.moves.length));
      case 'gomoku':
        gomoku.place(Cell(7, 7 + gomoku.moves.length));
      case 'chess':
        if (chess.moves.isEmpty) chess.applyMove(parseUciMove('e1g1'));
      case 'xiangqi':
        if (xiangqi.moves.isEmpty) {
          xiangqi.applyMove(parseXiangqiUciMove('b2b9'));
        }
      default:
        if (draughts.moves.isEmpty) {
          draughts.applyMove(draughts.legalMoves().single);
        }
    }
  });
  void undo() => _mutate(() {
    switch (game) {
      case 'go':
        go.undo();
      case 'gomoku':
        gomoku.undo();
      case 'chess':
        chess.undo();
      case 'xiangqi':
        xiangqi.undo();
      default:
        draughts.undo();
    }
  });
  void flip() => _mutate(() => flipped = !flipped);
  BoardMotionScene<Object>? _scene() {
    _boardBounds = null;
    _lastMoveTrail = null;
    BoardMotionScene<Object>? result;
    void visit(Element e) {
      final w = e.widget;
      if (w is AnimatedBuilder && w.animation is BoardMotionScene<Object>) {
        result = w.animation as BoardMotionScene<Object>;
      } else if (w is CustomPaint) {
        if (w.key == const ValueKey('draughts-last-move-trail')) {
          final painter = w.painter as dynamic;
          _lastMoveTrail = {
            'path': [
              for (final cell in painter.path as List<Cell>)
                [cell.row, cell.col],
            ],
            'flipped': painter.flipped as bool,
          };
        }
        try {
          final scene = (w.painter as dynamic).motion;
          if (scene is BoardMotionScene<Object>) {
            result = scene;
            final render = e.findRenderObject();
            if (render is RenderBox && render.hasSize) {
              final origin = render.localToGlobal(Offset.zero);
              _boardBounds = {
                'x': origin.dx,
                'y': origin.dy,
                'width': render.size.width,
                'height': render.size.height,
              };
            }
          }
        } on NoSuchMethodError {
          /* Other framework painters. */
        }
      }
      if (result == null) e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return result;
  }

  Map<String, Object?> snapshot() {
    final scene = _scene();
    return {
      'game': game,
      'generation': generation,
      'renderedGeneration': renderedGeneration,
      'reduced': reduced,
      'active': scene?.isAnimating ?? false,
      'moves': switch (game) {
        'go' => go.moves.length,
        'gomoku' => gomoku.moves.length,
        'chess' => chess.moves.length,
        'xiangqi' => xiangqi.moves.length,
        _ => draughts.moves.length,
      },
      'lastTap': lastTap == null ? null : [lastTap!.row, lastTap!.col],
      'boardBounds': _boardBounds,
      'lastMoveTrail': _lastMoveTrail,
      'frames': [
        for (final p in scene?.frames ?? <BoardPieceFrame<Object>>[])
          {
            'x': p.position.dx,
            'y': p.position.dy,
            'moving': p.moving,
            'departing': p.departing,
            'scale': p.scale,
            'opacity': p.opacity,
          },
      ],
    };
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff526b50),
      useMaterial3: true,
    ),
    home: Builder(
      builder: (context) {
        // Session mutations are immediate, but the painters and motion scene
        // still describe the preceding frame until this build is complete.
        // Browser assertions must wait for this acknowledgement before mixing
        // session counts with observations of the actual rendered widget tree.
        final buildingGeneration = generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) renderedGeneration = buildingGeneration;
        });
        reduced = MediaQuery.disableAnimationsOf(context);
        return Scaffold(
          appBar: AppBar(title: const Text('EasyPlay · 行棋动画')),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Text(label, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('轻量过渡 · 即时操作'),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: KeyedSubtree(
                      key: ValueKey(game),
                      child: switch (game) {
                        'go' => Board(
                          type: GameType.go,
                          session: go,
                          selected: null,
                          targets: const [],
                          onCell: (cell) => _mutate(() {
                            lastTap = cell;
                            go.placeGo(cell);
                          }),
                        ),
                        'gomoku' => GomokuBoard(
                          session: gomoku,
                          placementMode: GoPlacementMode.direct,
                          onCell: (cell) => _mutate(() => gomoku.place(cell)),
                        ),
                        'chess' => ChessBoard(session: chess, onCell: null),
                        'xiangqi' => XiangqiBoard(
                          session: xiangqi,
                          onCell: (cell) => _mutate(() => lastTap = cell),
                        ),
                        _ => DraughtsBoard(
                          session: draughts,
                          onCell: (_) {},
                          flipped: flipped,
                        ),
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(onPressed: move, child: const Text('演示行棋')),
                    const SizedBox(width: 12),
                    OutlinedButton(onPressed: undo, child: const Text('悔棋')),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    ),
  );
}
