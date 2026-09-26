import 'dart:math';

enum GameType { go, chess, checkers }

enum Side { black, white }

enum PieceKind { stone, pawn, rook, knight, bishop, queen, king, checker }

enum GoRuleSet { chinese, japanese, korean }

extension GoRuleSetX on GoRuleSet {
  String get label => switch (this) {
    GoRuleSet.chinese => '中国规则',
    GoRuleSet.japanese => '日本规则',
    GoRuleSet.korean => '韩国规则',
  };

  String get sgfName => switch (this) {
    GoRuleSet.chinese => 'Chinese',
    GoRuleSet.japanese => 'Japanese',
    GoRuleSet.korean => 'Korean',
  };
}

class GoConfig {
  final int boardSize;
  final GoRuleSet rules;
  final double komi;
  final int handicap;

  const GoConfig({
    this.boardSize = 19,
    this.rules = GoRuleSet.chinese,
    double? komi,
    this.handicap = 0,
  }) : komi = komi ?? (rules == GoRuleSet.chinese ? 7.5 : 6.5),
       assert(boardSize == 9 || boardSize == 13 || boardSize == 19),
       assert(handicap >= 0 && handicap <= 9),
       assert((komi ?? (rules == GoRuleSet.chinese ? 7.5 : 6.5)) >= -100),
       assert((komi ?? (rules == GoRuleSet.chinese ? 7.5 : 6.5)) <= 100);

  void validate() {
    if (![9, 13, 19].contains(boardSize) ||
        handicap < 0 ||
        handicap > 9 ||
        handicap == 1 ||
        !komi.isFinite ||
        komi < -100 ||
        komi > 100) {
      throw ArgumentError('棋盘须为9/13/19路，让子为0或2–9，贴目须为-100至100的有限数值');
    }
  }

  GoConfig copyWith({
    int? boardSize,
    GoRuleSet? rules,
    double? komi,
    int? handicap,
  }) => GoConfig(
    boardSize: boardSize ?? this.boardSize,
    rules: rules ?? this.rules,
    komi:
        komi ??
        (rules != null && rules != this.rules
            ? (rules == GoRuleSet.chinese ? 7.5 : 6.5)
            : this.komi),
    handicap: handicap ?? this.handicap,
  );
}

class GoScore {
  final double black;
  final double white;
  final GoRuleSet rules;
  final Side? winnerOverride;
  final double? marginOverride;
  final bool resignation;
  const GoScore({
    required this.black,
    required this.white,
    required this.rules,
    this.winnerOverride,
    this.marginOverride,
    this.resignation = false,
  });
  double get margin => marginOverride ?? (black - white).abs();
  Side? get winner =>
      winnerOverride ??
      (black == white ? null : (black > white ? Side.black : Side.white));
  String get result => resignation
      ? '${winner == Side.black ? '黑' : '白'}中盘胜'
      : winner == null
      ? '和棋'
      : '${winner == Side.black ? '黑' : '白'}胜 ${margin.toStringAsFixed(margin == margin.roundToDouble() ? 0 : 1)}目';
}

extension SideX on Side {
  Side get opponent => this == Side.black ? Side.white : Side.black;
  String get label => this == Side.black ? '黑方' : '白方';
}

class Cell {
  final int row;
  final int col;
  const Cell(this.row, this.col);
  @override
  bool operator ==(Object other) =>
      other is Cell && row == other.row && col == other.col;
  @override
  int get hashCode => Object.hash(row, col);
}

class GamePiece {
  final Side side;
  final PieceKind kind;
  const GamePiece(this.side, this.kind);
  GamePiece copy() => GamePiece(side, kind);
}

class GameMove {
  final Cell? from;
  final Cell to;
  final bool captured;
  final bool pass;
  final Side? side;
  const GameMove({
    this.from,
    required this.to,
    this.captured = false,
    this.pass = false,
    this.side,
  });
}

class _Snapshot {
  final List<List<GamePiece?>> board;
  final Side turn;
  final int blackCaptures;
  final int whiteCaptures;
  final bool gameOver;
  final Side? winner;
  final int moveCount;
  final List<String> positions;
  final int consecutivePasses;
  _Snapshot(
    this.board,
    this.turn,
    this.blackCaptures,
    this.whiteCaptures,
    this.gameOver,
    this.winner,
    this.moveCount,
    this.positions,
    this.consecutivePasses,
  );
}

/// Rules and mutable state for the playable prototype. Chess intentionally omits castling/en-passant;
/// checkers supports single jumps and promotion; Go supports captures, suicide prevention and simple ko.
class GameSession {
  final GameType type;
  GoConfig _goConfig;
  GoConfig get goConfig => _goConfig;
  bool goScoreConfirmed = false;
  Side? goResignedSide;
  Side? _adjudicatedWinner;
  double? _adjudicatedMargin;
  late List<List<GamePiece?>> initialGoBoard;
  Side initialGoTurn = Side.black;
  int revision = 0;
  late List<List<GamePiece?>> board;
  Side turn = Side.black;
  int blackCaptures = 0;
  int whiteCaptures = 0;
  bool gameOver = false;
  Side? winner;
  final List<GameMove> moves = [];

  /// Stones marked dead during the scoring phase; the board itself is kept intact.
  final Set<Cell> deadGoStones = <Cell>{};
  final List<_Snapshot> _undo = [];
  final List<String> _positions = [];
  int _consecutivePasses = 0;

  GameSession(this.type, {GoConfig? goConfig})
    : _goConfig = goConfig ?? const GoConfig() {
    reset();
  }
  int get size => type == GameType.go ? goConfig.boardSize : 8;
  GamePiece? pieceAt(Cell cell) =>
      inside(cell) ? board[cell.row][cell.col] : null;
  bool inside(Cell c) =>
      c.row >= 0 && c.col >= 0 && c.row < size && c.col < size;
  String get turnLabel => type == GameType.go && gameOver
      ? (goScoreConfirmed ? calculateGoScore().result : '待确认计分')
      : gameOver
      ? (winner == null ? '平局' : '${winner!.label}获胜')
      : '${turn.label}回合';
  bool get isInCheckTurn => type == GameType.chess && _isInCheck(turn);

  void setGoConfig(GoConfig config) {
    if (type != GameType.go) return;
    config.validate();
    _goConfig = config;
    reset();
  }

  bool toggleDeadGoStone(Cell cell) {
    if (type != GameType.go ||
        !gameOver ||
        goScoreConfirmed ||
        pieceAt(cell) == null) {
      return false;
    }
    final group = _groupOn(board, cell).$1;
    if (deadGoStones.contains(cell)) {
      deadGoStones.removeAll(group);
    } else {
      deadGoStones.addAll(group);
    }
    return true;
  }

  bool confirmGoScore() {
    if (type != GameType.go || !gameOver) return false;
    winner = calculateGoScore().winner;
    goScoreConfirmed = true;
    return true;
  }

  /// Applies KataGo's end-position adjudication. Its life/death search leaves
  /// seki groups alive, while final_score accounts for the selected ruleset.
  void adjudicateGo(
    Set<Cell> dead, {
    required Side? adjudicatedWinner,
    required double margin,
  }) {
    if (type != GameType.go || !gameOver || !margin.isFinite || margin < 0) {
      throw StateError('当前局面无法应用围棋终局裁定');
    }
    deadGoStones.clear();
    final visited = <Cell>{};
    for (final cell in dead) {
      if (!inside(cell) || pieceAt(cell) == null || visited.contains(cell)) {
        continue;
      }
      final group = _groupOn(board, cell).$1;
      deadGoStones.addAll(group);
      visited.addAll(group);
    }
    _adjudicatedWinner = adjudicatedWinner;
    _adjudicatedMargin = margin;
    winner = adjudicatedWinner;
    goScoreConfirmed = true;
  }

  bool resumeGo() {
    if (type != GameType.go || !gameOver) return false;
    if (goResignedSide != null) return undo();
    // Remove both ending passes so continuing cannot immediately end again.
    while (moves.isNotEmpty && moves.last.pass) {
      undo();
    }
    deadGoStones.clear();
    goScoreConfirmed = false;
    goResignedSide = null;
    _adjudicatedWinner = null;
    _adjudicatedMargin = null;
    winner = null;
    return true;
  }

  /// Establish an SGF setup position before replay. No synthetic pass moves.
  void setupGo(Map<Cell, Side> stones, Side next) {
    if (type != GameType.go || moves.isNotEmpty) {
      throw StateError('摆子只能用于初始局面');
    }
    if (stones.keys.any((c) => !inside(c))) {
      throw ArgumentError('摆子超出棋盘');
    }
    board = List.generate(size, (_) => List<GamePiece?>.filled(size, null));
    for (final entry in stones.entries) {
      board[entry.key.row][entry.key.col] = GamePiece(
        entry.value,
        PieceKind.stone,
      );
    }
    turn = next;
    initialGoTurn = next;
    initialGoBoard = _copyBoard(board);
    _positions
      ..clear()
      ..add(_signature(board));
  }

  void reset() {
    if (type == GameType.go) goConfig.validate();
    revision++;
    goScoreConfirmed = false;
    goResignedSide = null;
    _adjudicatedWinner = null;
    _adjudicatedMargin = null;
    board = List.generate(size, (_) => List<GamePiece?>.filled(size, null));
    turn = Side.black;
    blackCaptures = 0;
    whiteCaptures = 0;
    gameOver = false;
    winner = null;
    moves.clear();
    deadGoStones.clear();
    _undo.clear();
    _positions.clear();
    _consecutivePasses = 0;
    if (type == GameType.chess) _setupChess();
    if (type == GameType.checkers) _setupCheckers();
    if (type == GameType.go && goConfig.handicap > 0) {
      for (final point in _handicapPoints(goConfig.boardSize)) {
        board[point.row][point.col] = const GamePiece(
          Side.black,
          PieceKind.stone,
        );
      }
      turn = Side.white;
    }
    initialGoBoard = _copyBoard(board);
    initialGoTurn = turn;
    _positions.add(_signature(board));
  }

  List<Cell> _handicapPoints(int boardSize) {
    final d = boardSize >= 13 ? 3 : 2;
    final m = boardSize - 1 - d;
    final center = boardSize ~/ 2;
    final corners = [Cell(d, m), Cell(m, d), Cell(m, m), Cell(d, d)];
    final count = goConfig.handicap;
    if (count <= 4) return corners.take(count).toList();
    return [
      ...corners,
      if (count >= 6) ...[Cell(center, d), Cell(center, m)],
      if (count >= 8) ...[Cell(d, center), Cell(m, center)],
      if (count.isOdd) Cell(center, center),
    ];
  }

  void _setupChess() {
    const back = [
      PieceKind.rook,
      PieceKind.knight,
      PieceKind.bishop,
      PieceKind.queen,
      PieceKind.king,
      PieceKind.bishop,
      PieceKind.knight,
      PieceKind.rook,
    ];
    for (var c = 0; c < 8; c++) {
      board[0][c] = GamePiece(Side.black, back[c]);
      board[1][c] = const GamePiece(Side.black, PieceKind.pawn);
      board[6][c] = const GamePiece(Side.white, PieceKind.pawn);
      board[7][c] = GamePiece(Side.white, back[c]);
    }
  }

  void _setupCheckers() {
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 8; c++) {
        if ((r + c).isOdd) {
          board[r][c] = const GamePiece(Side.black, PieceKind.checker);
        }
      }
    }
    for (var r = 5; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        if ((r + c).isOdd) {
          board[r][c] = const GamePiece(Side.white, PieceKind.checker);
        }
      }
    }
  }

  bool placeGo(Cell cell) {
    if (type != GameType.go || gameOver || !_canPlayGo(cell, turn)) {
      return false;
    }
    _save();
    final captured = _applyGo(board, cell, turn);
    if (turn == Side.black) {
      blackCaptures += captured;
    } else {
      whiteCaptures += captured;
    }
    moves.add(GameMove(to: cell, captured: captured > 0, side: turn));
    _consecutivePasses = 0;
    _finishTurn();
    _positions.add(_signature(board));
    return true;
  }

  bool isLegalGoMove(Cell cell) =>
      type == GameType.go && !gameOver && _canPlayGo(cell, turn);

  bool resignGo([Side? side]) {
    if (type != GameType.go || gameOver) return false;
    _save();
    goResignedSide = side ?? turn;
    winner = goResignedSide!.opponent;
    gameOver = true;
    goScoreConfirmed = true;
    return true;
  }

  bool passGo() {
    if (type != GameType.go || gameOver) return false;
    _save();
    moves.add(GameMove(to: const Cell(-1, -1), pass: true, side: turn));
    _consecutivePasses++;
    if (_consecutivePasses >= 2) gameOver = true;
    _finishTurn();
    _positions.add(_signature(board));
    return true;
  }

  List<Cell> legalMovesFrom(Cell from) {
    if (gameOver || !inside(from)) return const [];
    final piece = board[from.row][from.col];
    if (piece == null || piece.side != turn || type == GameType.go) {
      return const [];
    }
    if (type == GameType.checkers) {
      final all = _allCheckerMoves(turn);
      return all.where((m) => m.from == from).map((m) => m.to).toList();
    }
    return _chessPseudoMoves(from, piece).where((to) {
      if (board[to.row][to.col]?.kind == PieceKind.king) return false;
      final test = _copyBoard(board);
      _moveOn(test, from, to, promote: true);
      return !_isInCheck(turn, test);
    }).toList();
  }

  bool movePiece(Cell from, Cell to) {
    if (gameOver || type == GameType.go || !inside(from) || !inside(to)) {
      return false;
    }
    final piece = board[from.row][from.col];
    if (piece == null ||
        piece.side != turn ||
        !legalMovesFrom(from).contains(to)) {
      return false;
    }
    _save();
    final capturedPiece = board[to.row][to.col];
    _moveOn(board, from, to, promote: true);
    final captured =
        capturedPiece != null ||
        (type == GameType.checkers && (from.row - to.row).abs() == 2);
    if (captured) {
      if (turn == Side.black) {
        blackCaptures++;
      } else {
        whiteCaptures++;
      }
      if (type == GameType.checkers) {
        board[(from.row + to.row) ~/ 2][(from.col + to.col) ~/ 2] = null;
      }
    }
    moves.add(GameMove(from: from, to: to, captured: captured));
    final movedSide = turn;
    _finishTurn();
    if (type == GameType.chess) {
      if (!_hasAnyLegalMove(turn)) {
        gameOver = true;
        winner = _isInCheck(turn) ? movedSide : null;
      }
    } else if (type == GameType.checkers && !_hasAnyLegalMove(turn)) {
      gameOver = true;
      winner = movedSide;
    }
    _positions.add(_signature(board));
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    final s = _undo.removeLast();
    board = _copyBoard(s.board);
    turn = s.turn;
    blackCaptures = s.blackCaptures;
    whiteCaptures = s.whiteCaptures;
    gameOver = s.gameOver;
    winner = s.winner;
    while (moves.length > s.moveCount) {
      moves.removeLast();
    }
    _positions
      ..clear()
      ..addAll(s.positions);
    _consecutivePasses = s.consecutivePasses;
    deadGoStones.clear();
    goScoreConfirmed = false;
    goResignedSide = null;
    _adjudicatedWinner = null;
    _adjudicatedMargin = null;
    return true;
  }

  GoScore calculateGoScore() {
    if (type != GameType.go) {
      throw StateError('Go scoring is only available for a Go session');
    }
    var black = 0.0;
    var white = goConfig.komi;
    final visited = <Cell>{};
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final cell = Cell(r, c);
        final piece = board[r][c];
        final isDead = deadGoStones.contains(cell);
        if (piece != null && !isDead) {
          if (goConfig.rules == GoRuleSet.chinese) {
            if (piece.side == Side.black) {
              black++;
            } else {
              white++;
            }
          }
          continue;
        }
        if (visited.contains(cell)) continue;
        final region = <Cell>{};
        final borders = <Side>{};
        final stack = <Cell>[cell];
        while (stack.isNotEmpty) {
          final current = stack.removeLast();
          if (!inside(current) || !region.add(current)) continue;
          for (final n in _neighbors(current)) {
            if (!inside(n)) continue;
            final p = deadGoStones.contains(n) ? null : board[n.row][n.col];
            if (p == null) {
              stack.add(n);
            } else {
              borders.add(p.side);
            }
          }
        }
        visited.addAll(region);
        if (borders.length == 1) {
          if (borders.single == Side.black) black += region.length;
          if (borders.single == Side.white) white += region.length;
        }
      }
    }
    if (goConfig.rules != GoRuleSet.chinese) {
      black += blackCaptures;
      white += whiteCaptures;
    }
    for (final cell
        in goConfig.rules == GoRuleSet.chinese ? <Cell>{} : deadGoStones) {
      final piece = board[cell.row][cell.col];
      if (piece?.side == Side.black) {
        white++;
      } else if (piece?.side == Side.white) {
        black++;
      }
    }
    return GoScore(
      black: black,
      white: white,
      rules: goConfig.rules,
      winnerOverride: goResignedSide?.opponent ?? _adjudicatedWinner,
      resignation: goResignedSide != null,
      marginOverride: _adjudicatedMargin,
    );
  }

  Iterable<GameMove> _allCheckerMoves(Side side) {
    final moves = <GameMove>[];
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p == null || p.side != side) continue;
        final forward = side == Side.white ? -1 : 1;
        final dirs = p.kind == PieceKind.king ? const [-1, 1] : [forward];
        for (final dr in dirs) {
          for (final dc in const [-1, 1]) {
            final one = Cell(r + dr, c + dc);
            if (inside(one) && board[one.row][one.col] == null) {
              moves.add(GameMove(from: Cell(r, c), to: one));
            }
            final two = Cell(r + dr * 2, c + dc * 2);
            if (inside(two) &&
                board[two.row][two.col] == null &&
                inside(one) &&
                board[one.row][one.col]?.side == side.opponent) {
              moves.add(GameMove(from: Cell(r, c), to: two, captured: true));
            }
          }
        }
      }
    }
    final captures = moves.where((m) => m.captured).toList();
    return captures.isNotEmpty ? captures : moves;
  }

  List<Cell> _chessPseudoMoves(Cell from, GamePiece p) {
    final result = <Cell>[];
    void addStep(int dr, int dc) {
      final to = Cell(from.row + dr, from.col + dc);
      if (inside(to) && board[to.row][to.col]?.side != p.side) result.add(to);
    }

    if (p.kind == PieceKind.knight) {
      for (final d in const [
        (2, 1),
        (2, -1),
        (-2, 1),
        (-2, -1),
        (1, 2),
        (1, -2),
        (-1, 2),
        (-1, -2),
      ]) {
        addStep(d.$1, d.$2);
      }
    } else if (p.kind == PieceKind.king) {
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          if (dr != 0 || dc != 0) addStep(dr, dc);
        }
      }
    } else if (p.kind == PieceKind.pawn) {
      final dir = p.side == Side.white ? -1 : 1;
      final one = Cell(from.row + dir, from.col);
      if (inside(one) && board[one.row][one.col] == null) {
        result.add(one);
        final start = p.side == Side.white ? 6 : 1;
        final two = Cell(from.row + dir * 2, from.col);
        if (from.row == start && board[two.row][two.col] == null) {
          result.add(two);
        }
      }
      for (final dc in [-1, 1]) {
        final to = Cell(from.row + dir, from.col + dc);
        if (inside(to) && board[to.row][to.col]?.side == p.side.opponent) {
          result.add(to);
        }
      }
    } else {
      final dirs = <(int, int)>[];
      if (p.kind == PieceKind.rook || p.kind == PieceKind.queen) {
        dirs.addAll(const [(1, 0), (-1, 0), (0, 1), (0, -1)]);
      }
      if (p.kind == PieceKind.bishop || p.kind == PieceKind.queen) {
        dirs.addAll(const [(1, 1), (1, -1), (-1, 1), (-1, -1)]);
      }
      for (final d in dirs) {
        var r = from.row + d.$1, c = from.col + d.$2;
        while (inside(Cell(r, c))) {
          final target = board[r][c];
          if (target == null) {
            result.add(Cell(r, c));
          } else {
            if (target.side != p.side) result.add(Cell(r, c));
            break;
          }
          r += d.$1;
          c += d.$2;
        }
      }
    }
    return result;
  }

  bool _isInCheck(Side side, [List<List<GamePiece?>>? state]) {
    final b = state ?? board;
    Cell? king;
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final p = b[r][c];
        if (p?.side == side && p?.kind == PieceKind.king) king = Cell(r, c);
      }
    }
    if (king == null) return false;
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final p = b[r][c];
        if (p == null || p.side == side) continue;
        if (_attacks(b, Cell(r, c), king, p)) return true;
      }
    }
    return false;
  }

  bool _attacks(List<List<GamePiece?>> b, Cell from, Cell target, GamePiece p) {
    final dr = target.row - from.row, dc = target.col - from.col;
    if (p.kind == PieceKind.pawn) {
      return dr == (p.side == Side.white ? -1 : 1) && dc.abs() == 1;
    }
    if (p.kind == PieceKind.knight) {
      return (dr.abs() == 2 && dc.abs() == 1) ||
          (dr.abs() == 1 && dc.abs() == 2);
    }
    if (p.kind == PieceKind.king) return max(dr.abs(), dc.abs()) == 1;
    final diagonal = dr.abs() == dc.abs() && dr != 0;
    final straight = (dr == 0) != (dc == 0);
    if (!((p.kind == PieceKind.bishop && diagonal) ||
        (p.kind == PieceKind.rook && straight) ||
        (p.kind == PieceKind.queen && (diagonal || straight)))) {
      return false;
    }
    final sr = dr == 0 ? 0 : dr ~/ dr.abs(), sc = dc == 0 ? 0 : dc ~/ dc.abs();
    var r = from.row + sr, c = from.col + sc;
    while (r != target.row || c != target.col) {
      if (b[r][c] != null) return false;
      r += sr;
      c += sc;
    }
    return true;
  }

  bool _hasAnyLegalMove(Side side) {
    final old = turn;
    turn = side;
    var found = false;
    for (var r = 0; r < size && !found; r++) {
      for (var c = 0; c < size && !found; c++) {
        if (legalMovesFrom(Cell(r, c)).isNotEmpty) found = true;
      }
    }
    turn = old;
    return found;
  }

  void _moveOn(
    List<List<GamePiece?>> b,
    Cell from,
    Cell to, {
    required bool promote,
  }) {
    var p = b[from.row][from.col]!;
    b[from.row][from.col] = null;
    if (promote && p.kind == PieceKind.pawn && (to.row == 0 || to.row == 7)) {
      p = GamePiece(p.side, PieceKind.queen);
    }
    if (promote &&
        p.kind == PieceKind.checker &&
        (to.row == 0 || to.row == 7)) {
      p = GamePiece(p.side, PieceKind.king);
    }
    b[to.row][to.col] = p;
  }

  bool _canPlayGo(Cell cell, Side side) {
    if (!inside(cell) || board[cell.row][cell.col] != null) return false;
    final test = _copyBoard(board);
    _applyGo(test, cell, side);
    final own = _groupOn(test, cell);
    if (own.$2.isEmpty) return false;
    final signature = _signature(test);
    if (goConfig.rules == GoRuleSet.chinese) {
      return !_positions.contains(signature);
    }
    return _positions.length < 2 ||
        signature != _positions[_positions.length - 2];
  }

  int _applyGo(List<List<GamePiece?>> b, Cell cell, Side side) {
    var capturedCount = 0;
    b[cell.row][cell.col] = GamePiece(side, PieceKind.stone);
    final checked = <Cell>{};
    for (final n in _neighbors(cell)) {
      if (!inside(n) ||
          b[n.row][n.col]?.side != side.opponent ||
          checked.contains(n)) {
        continue;
      }
      final group = _groupOn(b, n);
      checked.addAll(group.$1);
      if (group.$2.isEmpty) {
        for (final point in group.$1) {
          b[point.row][point.col] = null;
          capturedCount++;
        }
      }
    }
    return capturedCount;
  }

  (Set<Cell>, Set<Cell>) _groupOn(List<List<GamePiece?>> b, Cell start) {
    final color = b[start.row][start.col]?.side;
    final group = <Cell>{}, liberties = <Cell>{}, stack = <Cell>[start];
    while (stack.isNotEmpty) {
      final cell = stack.removeLast();
      if (!group.add(cell)) continue;
      for (final n in _neighbors(cell)) {
        if (!inside(n)) continue;
        final p = b[n.row][n.col];
        if (p == null) {
          liberties.add(n);
        } else if (p.side == color && !group.contains(n)) {
          stack.add(n);
        }
      }
    }
    return (group, liberties);
  }

  Iterable<Cell> _neighbors(Cell p) sync* {
    yield Cell(p.row - 1, p.col);
    yield Cell(p.row + 1, p.col);
    yield Cell(p.row, p.col - 1);
    yield Cell(p.row, p.col + 1);
  }

  String _signature(List<List<GamePiece?>> b) => b
      .map(
        (row) => row
            .map(
              (p) => p == null
                  ? '.'
                  : p.side == Side.black
                  ? 'b'
                  : 'w',
            )
            .join(),
      )
      .join('/');
  List<List<GamePiece?>> _copyBoard(List<List<GamePiece?>> source) =>
      source.map((row) => row.map((p) => p?.copy()).toList()).toList();
  void _save() => _undo.add(
    _Snapshot(
      _copyBoard(board),
      turn,
      blackCaptures,
      whiteCaptures,
      gameOver,
      winner,
      moves.length,
      List.of(_positions),
      _consecutivePasses,
    ),
  );
  void _finishTurn() => turn = turn.opponent;
}
