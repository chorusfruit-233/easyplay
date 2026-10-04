import '../game_session.dart' show Cell, Side;
import 'gomoku_variant.dart';

enum GomokuForbidden {
  overline('长连禁手'),
  doubleFour('双四禁手'),
  doubleThree('双活三禁手');

  const GomokuForbidden(this.label);
  final String label;
}

class GomokuMoveAnalysis {
  const GomokuMoveAnalysis({
    required this.legal,
    this.winningLine = const [],
    this.forbidden,
    this.reason,
  });

  final bool legal;
  final List<Cell> winningLine;
  final GomokuForbidden? forbidden;
  final String? reason;
}

/// Analyze an unplayed intersection on a flat 15×15 board without changing it.
/// Renju uses the RIF's recursively defined real threes, with free openings.
GomokuMoveAnalysis analyzeGomokuMove(
  List<Side?> board,
  Cell cell,
  Side side, {
  GomokuVariant variant = GomokuVariant.freestyle,
  void Function()? checkBudget,
}) {
  if (board.length != 225) {
    throw ArgumentError.value(board.length, 'board.length', '棋盘须为15×15');
  }
  if (cell.row < 0 || cell.col < 0 || cell.row >= 15 || cell.col >= 15) {
    return const GomokuMoveAnalysis(legal: false, reason: '落子超出棋盘');
  }
  final index = cell.row * 15 + cell.col;
  if (board[index] != null) {
    return const GomokuMoveAnalysis(legal: false, reason: '该位置已有棋子');
  }
  checkBudget?.call();
  final analyzer = _Analyzer(List.of(board), checkBudget);
  analyzer.board[index] = side;
  final lines = analyzer.linesThrough(index, side);
  final winning = lines.where((line) {
    if (variant == GomokuVariant.freestyle ||
        (variant == GomokuVariant.renju && side == Side.white)) {
      return line.length >= 5;
    }
    return line.length == 5;
  }).firstOrNull;
  // RIF 9.2 exempts a move that simultaneously attains an exact five, even
  // when another direction also contains an otherwise forbidden structure.
  if (winning != null) {
    return GomokuMoveAnalysis(
      legal: true,
      winningLine: List.unmodifiable(winning.map(analyzer.cell)),
    );
  }
  if (variant == GomokuVariant.renju && side == Side.black) {
    final forbidden = analyzer.forbiddenAt(index);
    if (forbidden != null) {
      return GomokuMoveAnalysis(
        legal: false,
        forbidden: forbidden,
        reason: forbidden.label,
      );
    }
  }
  return const GomokuMoveAnalysis(legal: true);
}

class _Analyzer {
  _Analyzer(this.board, this.checkBudget);

  static const size = 15;
  static const directions = [(0, 1), (1, 0), (1, 1), (1, -1)];
  final List<Side?> board;
  final void Function()? checkBudget;
  final Map<String, GomokuForbidden?> _memo = {};

  Cell cell(int index) => Cell(index ~/ size, index % size);
  int? offset(int index, int dr, int dc, int distance) {
    final row = index ~/ size + dr * distance;
    final col = index % size + dc * distance;
    return row >= 0 && col >= 0 && row < size && col < size
        ? row * size + col
        : null;
  }

  List<List<int>> linesThrough(int index, Side side) {
    return [
      for (final (dr, dc) in directions) lineThrough(index, side, dr, dc),
    ];
  }

  List<int> lineThrough(int index, Side side, int dr, int dc) {
    final before = <int>[];
    final after = <int>[];
    for (var distance = 1; ; distance++) {
      final next = offset(index, dr, dc, -distance);
      if (next == null || board[next] != side) break;
      before.add(next);
    }
    for (var distance = 1; ; distance++) {
      final next = offset(index, dr, dc, distance);
      if (next == null || board[next] != side) break;
      after.add(next);
    }
    return [...before.reversed, index, ...after];
  }

  String _stateKey(int index) =>
      '$index:${board.map((side) => side == Side.black
          ? 'b'
          : side == Side.white
          ? 'w'
          : '.').join()}';

  /// Every recursive call adds a stone, so recursion terminates naturally;
  /// memoization avoids revisiting the same extension position. No depth limit
  /// approximates the RIF 9.3 definition or mislabels recursive fake threes.
  GomokuForbidden? forbiddenAt(int index) {
    checkBudget?.call();
    final key = _stateKey(index);
    if (_memo.containsKey(key)) return _memo[key];
    final lines = linesThrough(index, Side.black);
    if (lines.any((line) => line.length == 5)) {
      _memo[key] = null;
      return null;
    }
    if (lines.any((line) => line.length > 5)) {
      return _memo[key] = GomokuForbidden.overline;
    }
    if (_fours(index).length >= 2) {
      return _memo[key] = GomokuForbidden.doubleFour;
    }
    final threes = _threeExtensions(index);
    if (threes.length < 2) {
      _memo[key] = null;
      return null;
    }
    var realThrees = 0;
    for (final extensions in threes.values) {
      var real = false;
      for (final extension in extensions) {
        checkBudget?.call();
        board[extension] = Side.black;
        try {
          // A three's extension cannot simultaneously make five in any line.
          if (linesThrough(
            extension,
            Side.black,
          ).any((line) => line.length == 5)) {
            continue;
          }
          if (forbiddenAt(extension) == null) {
            real = true;
            break;
          }
        } finally {
          board[extension] = null;
        }
      }
      if (real && ++realThrees >= 2) {
        return _memo[key] = GomokuForbidden.doubleThree;
      }
    }
    _memo[key] = null;
    return null;
  }

  String _stonesKey(List<int> stones) => (List.of(stones)..sort()).join(',');

  Set<String> _fours(int index) {
    final fours = <String>{};
    for (final (dr, dc) in directions) {
      checkBudget?.call();
      for (var start = -4; start <= 0; start++) {
        checkBudget?.call();
        final stones = <int>[];
        int? empty;
        var valid = true;
        for (var step = 0; step < 5; step++) {
          final next = offset(index, dr, dc, start + step);
          if (next == null || board[next] == Side.white) {
            valid = false;
            break;
          }
          if (board[next] == Side.black) {
            stones.add(next);
          } else if (empty == null) {
            empty = next;
          } else {
            valid = false;
            break;
          }
        }
        if (!valid || stones.length != 4 || empty == null) continue;
        board[empty] = Side.black;
        final exactFive = lineThrough(empty, Side.black, dr, dc).length == 5;
        board[empty] = null;
        if (exactFive) fours.add(_stonesKey(stones));
      }
    }
    return fours;
  }

  Map<String, Set<int>> _threeExtensions(int index) {
    final threes = <String, Set<int>>{};
    for (final (dr, dc) in directions) {
      checkBudget?.call();
      for (var start = -3; start <= 0; start++) {
        checkBudget?.call();
        final before = offset(index, dr, dc, start - 1);
        final after = offset(index, dr, dc, start + 4);
        if (before == null ||
            after == null ||
            board[before] != null ||
            board[after] != null) {
          continue;
        }
        final farBefore = offset(index, dr, dc, start - 2);
        final farAfter = offset(index, dr, dc, start + 5);
        // Both ends must form an exact five, never merge into an overline.
        if ((farBefore != null && board[farBefore] == Side.black) ||
            (farAfter != null && board[farAfter] == Side.black)) {
          continue;
        }
        final stones = <int>[];
        int? empty;
        var valid = true;
        for (var step = 0; step < 4; step++) {
          final next = offset(index, dr, dc, start + step);
          if (next == null || board[next] == Side.white) {
            valid = false;
            break;
          }
          if (board[next] == Side.black) {
            stones.add(next);
          } else if (empty == null) {
            empty = next;
          } else {
            valid = false;
            break;
          }
        }
        if (valid && stones.length == 3 && empty != null) {
          threes.putIfAbsent(_stonesKey(stones), () => <int>{}).add(empty);
        }
      }
    }
    return threes;
  }
}
