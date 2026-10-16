import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game_session.dart' show Cell;

/// Paths use board coordinates, so rotation and resizing remain view concerns.
class BoardMoveMotion {
  BoardMoveMotion({
    required List<List<Cell>> paths,
    Map<Cell, double> captureAt = const {},
  }) : paths = _snapshotPaths(paths),
       captureAt = Map.unmodifiable({
         for (final entry in captureAt.entries)
           entry.key: entry.value.isFinite
               ? entry.value.clamp(0.0, 1.0).toDouble()
               : 0.0,
       });

  factory BoardMoveMotion.alongPath(List<Cell> path, List<Cell> captures) {
    final points = _snapshotPaths([path]).single;
    if (captures.length > points.length - 1) {
      throw ArgumentError('more captures than path segments');
    }
    if (captures.toSet().length != captures.length) {
      throw ArgumentError('a captured cell cannot appear twice');
    }
    final times = <Cell, double>{};
    for (var i = 0; i < captures.length; i++) {
      final start = _point(points[i]);
      final length = (_point(points[i + 1]) - start).distance;
      final crossing = ((_point(captures[i]) - start).distance / length).clamp(
        0.0,
        1.0,
      );
      // Flying kings may cross a captured piece well before the midpoint.
      // Invert the same easing used for movement to fade at that crossing.
      var low = 0.0, high = 1.0;
      for (var step = 0; step < 20; step++) {
        final mid = (low + high) / 2;
        if (Curves.easeInOutCubic.transform(mid) < crossing) {
          low = mid;
        } else {
          high = mid;
        }
      }
      times[captures[i]] = (i + (low + high) / 2) / (points.length - 1);
    }
    return BoardMoveMotion(paths: [points], captureAt: times);
  }

  final List<List<Cell>> paths;
  final Map<Cell, double> captureAt;

  static List<List<Cell>> _snapshotPaths(List<List<Cell>> paths) {
    final snapshot = List<List<Cell>>.unmodifiable([
      for (final path in paths) List<Cell>.unmodifiable(path),
    ]);
    for (final path in snapshot) {
      if (path.isEmpty) {
        throw ArgumentError('a move path cannot be empty');
      }
      for (var i = 1; i < path.length; i++) {
        if (path[i - 1] == path[i]) {
          throw ArgumentError('a path segment cannot have zero length');
        }
      }
    }
    return snapshot;
  }
}

class BoardPieceFrame<T extends Object> {
  const BoardPieceFrame({
    required this.piece,
    required this.position,
    required this.destination,
    this.opacity = 1,
    this.scale = 1,
    this.moving = false,
    this.departing = false,
  });
  final T piece;
  final Offset position;
  final Cell destination;
  final double opacity, scale;
  final bool moving, departing;
}

Offset _point(Cell cell) => Offset(cell.col.toDouble(), cell.row.toDouble());

/// Visual state only. Sessions commit immediately; no timers delay game actions.
/// Painters listen directly, without rebuilding the board's input/semantics tree.
class BoardMotionScene<T extends Object> extends ChangeNotifier {
  BoardMotionScene(TickerProvider vsync)
    : _clock = AnimationController(vsync: vsync, value: 1) {
    _clock.addListener(notifyListeners);
  }

  final AnimationController _clock;
  Map<Cell, T> _current = {};
  List<Object> _history = [];
  Object? _configuration;
  bool _initialized = false;
  final _moving = <(T, List<Cell>)>[];
  final _departing = <(Cell, T, double)>[];
  final _destinations = <Cell>{};

  bool get isAnimating => _clock.isAnimating;

  void update({
    required Map<Cell, T> pieces,
    required List<Object> history,
    required Object Function(T) pieceKey,
    required Object configuration,
    required BoardMoveMotion? move,
    required bool animate,
  }) {
    final previous = _current;
    final singleMove =
        _initialized &&
        _configuration == configuration &&
        history.length == _history.length + 1 &&
        listEquals(_history, history.take(_history.length).toList());
    final unchanged =
        _initialized &&
        _configuration == configuration &&
        listEquals(_history, history) &&
        previous.length == pieces.length &&
        pieces.entries.every(
          (e) =>
              previous[e.key] != null &&
              pieceKey(previous[e.key]!) == pieceKey(e.value),
        );
    if (unchanged) {
      if (!animate) finish();
      return;
    }

    // A newer move replaces unfinished visuals; never queue stale board states.
    _clock.stop();
    _moving.clear();
    _departing.clear();
    _destinations.clear();
    _current = Map.unmodifiable(pieces);
    _history = List.unmodifiable(history);
    _configuration = configuration;
    _initialized = true;
    if (!animate || !singleMove || move == null || move.paths.isEmpty) {
      finish();
      return;
    }

    final sources = <Cell>{};
    for (final path in move.paths) {
      if (path.isEmpty ||
          pieces[path.last] == null ||
          (path.length > 1 && previous[path.first] == null) ||
          (path.length == 1 && previous[path.first] != null)) {
        finish();
        return;
      }
      sources.add(path.first);
      _destinations.add(path.last);
      _moving.add((previous[path.first] ?? pieces[path.last]!, path));
    }
    for (final entry in pieces.entries) {
      if (_destinations.contains(entry.key)) continue;
      if (previous[entry.key] == null ||
          pieceKey(previous[entry.key]!) != pieceKey(entry.value)) {
        finish();
        return;
      }
    }
    for (final entry in previous.entries) {
      if (sources.contains(entry.key)) continue;
      final now = pieces[entry.key];
      if (now == null || pieceKey(now) != pieceKey(entry.value)) {
        _departing.add((
          entry.key,
          entry.value,
          move.captureAt[entry.key] ?? 0,
        ));
      }
    }
    final segments = move.paths.map((p) => p.length - 1).reduce(math.max);
    _clock.duration = Duration(
      milliseconds: segments == 0 ? 180 : (segments * 140).clamp(240, 600),
    );
    _clock.forward(from: 0);
  }

  void finish() {
    _clock.stop();
    _moving.clear();
    _departing.clear();
    _destinations.clear();
    _clock.value = 1;
    notifyListeners();
  }

  Iterable<BoardPieceFrame<T>> get frames sync* {
    final progress = _clock.value;
    for (final entry in _current.entries) {
      if (progress < 1 && _destinations.contains(entry.key)) continue;
      yield BoardPieceFrame(
        piece: entry.value,
        position: _point(entry.key),
        destination: entry.key,
      );
    }
    if (progress >= 1) return;
    for (final (cell, piece, captureAt) in _departing) {
      final fadeWindow = math.min(.3, 1 - captureAt);
      // A capture at the endpoint stays visible until the final board replaces it.
      final fade = fadeWindow <= 0
          ? 0.0
          : ((progress - captureAt) / fadeWindow).clamp(0.0, 1.0).toDouble();
      if (fade >= 1) continue;
      yield BoardPieceFrame(
        piece: piece,
        position: _point(cell),
        destination: cell,
        opacity: 1 - fade,
        scale: 1 - fade * .12,
        departing: true,
      );
    }
    for (final (piece, path) in _moving) {
      if (path.length == 1) {
        final eased = Curves.easeOutCubic.transform(progress);
        yield BoardPieceFrame(
          piece: piece,
          position: _point(path.last),
          destination: path.last,
          opacity: .35 + .65 * eased,
          scale: .72 + .28 * eased,
          moving: true,
        );
      } else {
        final distance = progress * (path.length - 1);
        final index = math.min(distance.floor(), path.length - 2);
        final eased = Curves.easeInOutCubic.transform(distance - index);
        yield BoardPieceFrame(
          piece: piece,
          position: Offset.lerp(
            _point(path[index]),
            _point(path[index + 1]),
            eased,
          )!,
          destination: path.last,
          moving: true,
        );
      }
    }
  }

  void paint(
    Canvas canvas, {
    required Offset Function(Offset) center,
    required void Function(Canvas, T) piecePainter,
  }) {
    for (final frame in frames) {
      canvas.save();
      final at = center(frame.position);
      canvas.translate(at.dx, at.dy);
      canvas.scale(frame.scale);
      if (frame.opacity < 1) {
        canvas.saveLayer(
          null,
          Paint()..color = Colors.black.withValues(alpha: frame.opacity),
        );
      }
      piecePainter(canvas, frame.piece);
      if (frame.opacity < 1) canvas.restore();
      canvas.restore();
    }
  }

  @override
  void dispose() {
    _clock.removeListener(notifyListeners);
    _clock.dispose();
    super.dispose();
  }
}

class AnimatedBoard<T extends Object> extends StatefulWidget {
  const AnimatedBoard({
    super.key,
    required this.pieces,
    required this.history,
    required this.pieceKey,
    required this.configuration,
    required this.move,
    required this.builder,
  });
  final Map<Cell, T> pieces;
  final List<Object> history;
  final Object Function(T) pieceKey;
  final Object configuration;
  final BoardMoveMotion? move;
  final Widget Function(BuildContext, BoardMotionScene<T>) builder;

  @override
  State<AnimatedBoard<T>> createState() => _AnimatedBoardState<T>();
}

class _AnimatedBoardState<T extends Object> extends State<AnimatedBoard<T>>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _scene = BoardMotionScene<T>(this);
  bool _enabled = true;
  late bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _update();
  }

  @override
  void didUpdateWidget(covariant AnimatedBoard<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() => _scene.update(
    pieces: widget.pieces,
    history: widget.history,
    pieceKey: widget.pieceKey,
    configuration: widget.configuration,
    move: widget.move,
    animate: _enabled && _foreground,
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _scene.finish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _scene);
}
