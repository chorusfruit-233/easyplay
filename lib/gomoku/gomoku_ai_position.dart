part of 'gomoku_ai.dart';

/// A pattern describes what a move creates, not just the contiguous run.
/// Winning continuations are distinct intersections, so an open four and two
/// intersecting closed fours both require more than one defensive move.
class _Pattern {
  const _Pattern({
    this.wins = false,
    this.winningPoints = const [],
    this.threes = 0,
    this.score = 0,
  });

  final bool wins;
  final List<int> winningPoints;
  final int threes;
  final int score;
  bool get fork => winningPoints.length >= 2;
  bool get forcing => winningPoints.isNotEmpty;
}

class _Move {
  const _Move(this.index, this.analysis, this.attack, this.defense, this.order);
  final int index;
  final GomokuMoveAnalysis analysis;
  final _Pattern attack;
  final _Pattern defense;
  final int order;
}

class _SavedPattern {
  const _SavedPattern(this.index, this.black, this.white);
  final int index;
  final _Pattern? black;
  final _Pattern? white;
}

class _Undo {
  const _Undo(this.index, this.patterns, this.analysis);
  final int index;
  final List<_SavedPattern> patterns;
  final Map<(int, Side), GomokuMoveAnalysis> analysis;
}

class _Position {
  _Position(GomokuSession session)
    : board = [
        for (var row = 0; row < size; row++)
          for (var col = 0; col < size; col++) session.pieceAt(Cell(row, col)),
      ],
      turn = session.turn,
      count = session.moves.length,
      variant = session.variant {
    for (var index = 0; index < board.length; index++) {
      final side = board[index];
      if (side == null) continue;
      _neighbors(index, 1);
      _hash(index, side);
    }
  }

  static const size = gomokuBoardSize;
  static const directions = [(0, 1), (1, 0), (1, 1), (1, -1)];
  // Two independent 30-bit hashes work identically with Dart VM and JS bit ops.
  static final _zobristA = _keys(271828);
  static final _zobristB = _keys(314159);
  static List<int> _keys(int seed) {
    final random = Random(seed);
    return List.generate(size * size * 2, (_) => random.nextInt(1 << 30));
  }

  final List<Side?> board;
  final GomokuVariant variant;
  final _nearby = List<int>.filled(size * size, 0);
  final _black = List<_Pattern?>.filled(size * size, null);
  final _white = List<_Pattern?>.filled(size * size, null);
  final _undo = <_Undo>[];
  Map<(int, Side), GomokuMoveAnalysis> _analysis = {};
  int _hashA = 0;
  int _hashB = 0;
  Side turn;
  int count;

  (int, int, Side) get key => (_hashA, _hashB, turn);
  Cell cell(int index) => Cell(index ~/ size, index % size);
  bool inside(int row, int col) =>
      row >= 0 && col >= 0 && row < size && col < size;

  void _hash(int index, Side side) {
    final key = index * 2 + side.index;
    _hashA ^= _zobristA[key];
    _hashB ^= _zobristB[key];
  }

  void _neighbors(int index, int delta) {
    final row = index ~/ size, col = index % size;
    for (var dr = -2; dr <= 2; dr++) {
      for (var dc = -2; dc <= 2; dc++) {
        if (inside(row + dr, col + dc)) {
          _nearby[(row + dr) * size + col + dc] += delta;
        }
      }
    }
  }

  List<int> nearbyCells() => count == 0
      ? [size ~/ 2 * size + size ~/ 2]
      : [
          for (var i = 0; i < board.length; i++)
            if (board[i] == null && _nearby[i] > 0) i,
        ];

  Iterable<int> candidateCells() sync* {
    yield* nearbyCells();
    for (var i = 0; i < board.length; i++) {
      if (board[i] == null && _nearby[i] == 0 && count != 0) yield i;
    }
  }

  GomokuMoveAnalysis analysis(int index, Side side, void Function() check) =>
      _analysis.putIfAbsent(
        (index, side),
        () => analyzeGomokuMove(
          board,
          cell(index),
          side,
          variant: variant,
          checkBudget: check,
        ),
      );

  _Pattern pattern(int index, Side side) {
    final cache = side == Side.black ? _black : _white;
    return cache[index] ??= _pattern(index, side);
  }

  _Pattern _pattern(int index, Side side) {
    final exact =
        variant == GomokuVariant.standard ||
        (variant.hasForbiddenMoves && side == Side.black);
    final row = index ~/ size, col = index % size;
    final wins = <int>{};
    var threes = 0, closedThrees = 0, twos = 0;
    board[index] = side;
    try {
      for (final (dr, dc) in directions) {
        // Border and opposing stones both close a line; each window includes
        // the proposed move at offset 5. Five cells either side detect overlines.
        final line = List<int>.filled(11, 2);
        for (var d = -5; d <= 5; d++) {
          final r = row + dr * d, c = col + dc * d;
          if (inside(r, c)) {
            final piece = board[r * size + c];
            line[d + 5] = piece == null
                ? 0
                : piece == side
                ? 1
                : 2;
          }
        }
        var run = 1;
        for (final sign in [-1, 1]) {
          for (var d = 1; d <= 5 && line[5 + d * sign] == 1; d++) {
            run++;
          }
        }
        if (run >= 5 && (!exact || run == 5)) {
          return const _Pattern(wins: true, score: _Search.win);
        }
        final openGroups = <int>{}, threeGroups = <int>{}, twoGroups = <int>{};
        for (var start = 1; start <= 5; start++) {
          var stones = 0, mask = 0, empty = -1;
          var blocked = false;
          for (var s = start; s < start + 5; s++) {
            if (line[s] == 2) {
              blocked = true;
              break;
            }
            if (line[s] == 1) {
              stones++;
              mask |= 1 << s;
            } else {
              empty = s;
            }
          }
          if (blocked) continue;
          if (stones == 4 &&
              (!exact || (line[start - 1] != 1 && line[start + 5] != 1))) {
            final d = empty - 5;
            wins.add((row + dr * d) * size + col + dc * d);
          } else if (stones == 3) {
            threeGroups.add(mask);
          } else if (stones == 2) {
            twoGroups.add(mask);
          }
        }
        // Straight and broken live threes: one legal extension can produce a
        // contiguous four with two exact-five endpoints. Renju legality itself
        // is always checked by the shared rules before a move is searched.
        for (var start = 2; start <= 5; start++) {
          if (line[start - 1] != 0 || line[start + 4] != 0) continue;
          if (exact && (line[start - 2] == 1 || line[start + 5] == 1)) continue;
          var stones = 0, mask = 0, blocked = false;
          for (var s = start; s < start + 4; s++) {
            if (line[s] == 2) {
              blocked = true;
              break;
            }
            if (line[s] == 1) {
              stones++;
              mask |= 1 << s;
            }
          }
          if (!blocked && stones == 3) openGroups.add(mask);
        }
        threes += openGroups.length;
        closedThrees += threeGroups.difference(openGroups).length;
        twos += twoGroups.length;
      }
    } finally {
      board[index] = null;
    }
    final center = 20 - (row - 7).abs() - (col - 7).abs();
    final score =
        center +
        (wins.length >= 2
            ? 300000
            : wins.isNotEmpty
            ? 30000
            : 0) +
        threes * 3000 +
        (threes >= 2 ? 12000 : 0) +
        (wins.isNotEmpty && threes > 0 ? 40000 : 0) +
        closedThrees * 160 +
        twos * 12;
    return _Pattern(winningPoints: wins.toList(), threes: threes, score: score);
  }

  bool place(_Move move) {
    final index = move.index, row = index ~/ size, col = index % size;
    final affected = <int>{index};
    for (final (dr, dc) in directions) {
      for (var d = -5; d <= 5; d++) {
        final r = row + dr * d, c = col + dc * d;
        if (inside(r, c)) affected.add(r * size + c);
      }
    }
    final saved = <_SavedPattern>[];
    for (final i in affected) {
      saved.add(_SavedPattern(i, _black[i], _white[i]));
      _black[i] = null;
      _white[i] = null;
    }
    _undo.add(_Undo(index, saved, _analysis));
    _analysis = {};
    board[index] = turn;
    _hash(index, turn);
    _neighbors(index, 1);
    turn = turn.opponent;
    count++;
    return move.analysis.winningLine.isNotEmpty;
  }

  void undo() {
    final saved = _undo.removeLast();
    turn = turn.opponent;
    count--;
    _neighbors(saved.index, -1);
    _hash(saved.index, turn);
    board[saved.index] = null;
    for (final cache in saved.patterns) {
      _black[cache.index] = cache.black;
      _white[cache.index] = cache.white;
    }
    _analysis = saved.analysis;
  }
}
