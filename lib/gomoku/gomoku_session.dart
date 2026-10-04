import '../game_session.dart' show Cell, Side, SideX;
import 'gomoku_rules.dart';
import 'gomoku_variant.dart';

export 'gomoku_variant.dart';

const gomokuRulesVersion = 2;
const gomokuBoardSize = 15;

class GomokuMove {
  const GomokuMove(this.cell, this.side);

  final Cell cell;
  final Side side;

  Map<String, Object?> toJson() => {
    'row': cell.row,
    'col': cell.col,
    'side': side.name,
  };
}

/// Gomoku with free openings, no captures or passes. Renju rejects forbidden
/// black moves before changing any game state.
class GomokuSession {
  static const boardSize = gomokuBoardSize;

  final List<Side?> _board = List<Side?>.filled(boardSize * boardSize, null);
  final List<GomokuMove> _moves = [];
  Side _turn = Side.black;
  bool _gameOver = false;
  Side? _winner;
  Side? _resignedSide;
  List<Cell> _winningLine = [];
  int _revision = 0;

  GomokuSession({this.variant = GomokuVariant.freestyle});

  final GomokuVariant variant;

  int get size => boardSize;
  Side get turn => _turn;
  bool get gameOver => _gameOver;
  Side? get winner => _winner;
  bool get resigned => _resignedSide != null;
  int get revision => _revision;
  List<GomokuMove> get moves => List.unmodifiable(_moves);
  List<Cell> get winningLine => List.unmodifiable(_winningLine);
  List<List<Side?>> get board => List.unmodifiable([
    for (var row = 0; row < size; row++)
      List<Side?>.unmodifiable(_board.sublist(row * size, (row + 1) * size)),
  ]);

  bool inside(Cell cell) =>
      cell.row >= 0 && cell.col >= 0 && cell.row < size && cell.col < size;

  Side? pieceAt(Cell cell) =>
      inside(cell) ? _board[cell.row * size + cell.col] : null;

  String get resultLabel => !_gameOver
      ? ''
      : _winner == null
      ? '和棋'
      : '${_winner!.label}${resigned ? '中盘胜' : '获胜'}';
  String get turnLabel => _gameOver ? resultLabel : '${_turn.label}落子';

  GomokuMoveAnalysis _analyze(Cell cell) => _gameOver
      ? const GomokuMoveAnalysis(legal: false, reason: '对局已结束')
      : analyzeGomokuMove(_board, cell, _turn, variant: variant);

  bool canPlace(Cell cell) => _analyze(cell).legal;
  String? rejectionReason(Cell cell) => _analyze(cell).reason;

  bool place(Cell cell) {
    final analysis = _analyze(cell);
    if (!analysis.legal) return false;
    final side = _turn;
    _board[cell.row * size + cell.col] = side;
    _moves.add(GomokuMove(cell, side));
    _turn = side.opponent;
    _winningLine = List.of(analysis.winningLine);
    if (_winningLine.isNotEmpty) {
      _winner = side;
      _gameOver = true;
    } else if (_moves.length == size * size) {
      _gameOver = true;
    }
    _revision++;
    return true;
  }

  /// Resignation can be withdrawn without also removing the preceding stone.
  bool undo() {
    if (_resignedSide != null) {
      _resignedSide = null;
    } else {
      if (_moves.isEmpty) return false;
      final move = _moves.removeLast();
      _board[move.cell.row * size + move.cell.col] = null;
      _turn = move.side;
    }
    _gameOver = false;
    _winner = null;
    _winningLine = [];
    _revision++;
    return true;
  }

  bool resign(Side side) {
    if (_gameOver) return false;
    _resignedSide = side;
    _winner = side.opponent;
    _gameOver = true;
    _revision++;
    return true;
  }

  void reset() {
    _board.fillRange(0, _board.length, null);
    _moves.clear();
    _turn = Side.black;
    _gameOver = false;
    _winner = null;
    _resignedSide = null;
    _winningLine = [];
    _revision++;
  }

  GomokuSession fork() {
    final copy = GomokuSession(variant: variant);
    copy._board.setAll(0, _board);
    copy._moves.addAll(_moves);
    copy._turn = _turn;
    copy._gameOver = _gameOver;
    copy._winner = _winner;
    copy._resignedSide = _resignedSide;
    copy._winningLine = List.of(_winningLine);
    copy._revision = _revision;
    return copy;
  }

  Map<String, Object?> toJson() => {
    'version': gomokuRulesVersion,
    'variant': variant.name,
    'size': size,
    'moves': _moves.map((move) => move.toJson()).toList(),
    'turn': _turn.name,
    'gameOver': _gameOver,
    'winner': _winner?.name,
    'resigned': resigned,
    'resignedSide': _resignedSide?.name,
    'revision': _revision,
  };

  /// Treat imported/network state as an untrusted move record. Replaying every
  /// move rejects illegal turn order, duplicate cells and play after a result.
  factory GomokuSession.fromJson(Object? json) {
    if (json is! Map ||
        json['version'] is! int ||
        (json['version'] != 1 && json['version'] != gomokuRulesVersion) ||
        json['size'] is! int ||
        json['size'] != boardSize ||
        json['moves'] is! List ||
        json['gameOver'] is! bool ||
        json['resigned'] is! bool ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0) {
      throw const FormatException('无效的五子棋棋谱');
    }
    final GomokuVariant variant;
    if (json['version'] == 1 && !json.containsKey('variant')) {
      variant = GomokuVariant.freestyle;
    } else if (json['version'] == gomokuRulesVersion) {
      variant = GomokuVariant.fromName(json['variant']);
    } else {
      throw const FormatException('旧版五子棋棋谱不能包含规则字段');
    }
    final session = GomokuSession(variant: variant);
    final records = json['moves'] as List;
    if (records.length > boardSize * boardSize) {
      throw const FormatException('五子棋棋谱落子过多');
    }
    for (final record in records) {
      if (record is! Map ||
          record['row'] is! int ||
          record['col'] is! int ||
          record['side'] != session.turn.name ||
          !session.place(Cell(record['row'] as int, record['col'] as int))) {
        throw const FormatException('五子棋棋谱包含非法落子');
      }
    }
    final resignedSide = json['resignedSide'];
    if (json['resigned'] == true) {
      final side = switch (resignedSide) {
        'black' => Side.black,
        'white' => Side.white,
        _ => null,
      };
      if (side == null || !session.resign(side)) {
        throw const FormatException('无效的五子棋认输记录');
      }
    } else if (resignedSide != null) {
      throw const FormatException('五子棋认输状态不一致');
    }
    if (json['turn'] != session.turn.name ||
        json['gameOver'] != session.gameOver ||
        json['winner'] != session.winner?.name ||
        (json['revision'] as int) < session._revision) {
      throw const FormatException('五子棋棋谱状态与落子记录不一致');
    }
    session._revision = json['revision'] as int;
    return session;
  }
}
