import '../game_session.dart' show Cell, Side, SideX;
import 'gomoku_rules.dart';
import 'gomoku_variant.dart';
import 'gomoku_opening.dart';

export 'gomoku_variant.dart';
export 'gomoku_opening.dart';

const gomokuRulesVersion = 4;
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

/// Competitive Renju. Player identities remain fixed when colours exchange.
/// Legacy free-opening profiles exist solely for loading old records.
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
  bool _exchangeDecided = false;
  bool _secondExchangeDecided = false;
  int? _declaredProposals;
  bool _exchanged = false;
  final List<Cell> _proposals = [];
  final List<(Side, GomokuAction)> _actions = [];
  int _passes = 0;
  GomokuForbidden? _forbiddenLoss;

  GomokuSession({this.variant = GomokuVariant.soosyrv8});

  final GomokuVariant variant;

  int get size => boardSize;
  Side get turn => _turn;
  bool get gameOver => _gameOver;
  Side? get winner => _winner;
  bool get resigned => _resignedSide != null;
  int get revision => _revision;
  bool get exchanged => _exchanged;
  int? get declaredProposals => _declaredProposals;
  int get proposalCount =>
      variant == GomokuVariant.soosyrv8 ? (_declaredProposals ?? 0) : 2;
  bool get awaitingExchange =>
      phase == GomokuPhase.exchange || phase == GomokuPhase.secondExchange;
  bool get acceptsPlacement =>
      !awaitingExchange && phase != GomokuPhase.declaration;
  int get actionCount => variant.competitive ? _actions.length : _moves.length;
  Side? get lastActor =>
      variant.competitive ? _actions.lastOrNull?.$1 : _moves.lastOrNull?.side;
  List<Cell> get proposals => List.unmodifiable(_proposals);
  GomokuForbidden? get forbiddenLoss => _forbiddenLoss;
  GomokuPhase get phase {
    if (!variant.competitive) return GomokuPhase.normal;
    if (_moves.length < 3) return GomokuPhase.opening;
    if (!_exchangeDecided) return GomokuPhase.exchange;
    if (_moves.length == 3) return GomokuPhase.fourth;
    if (_moves.length == 4) {
      if (variant == GomokuVariant.soosyrv8) {
        if (_declaredProposals == null) return GomokuPhase.declaration;
        if (!_secondExchangeDecided) return GomokuPhase.secondExchange;
      }
      return _proposals.length < proposalCount
          ? GomokuPhase.proposals
          : GomokuPhase.selection;
    }
    return GomokuPhase.normal;
  }

  Side colorForPlayer(Side player) => _exchanged ? player.opponent : player;
  Side playerForColor(Side color) => colorForPlayer(color);
  Side get actor => switch (phase) {
    GomokuPhase.opening => Side.black,
    GomokuPhase.exchange => Side.white,
    GomokuPhase.declaration => playerForColor(Side.white),
    GomokuPhase.secondExchange => playerForColor(Side.black),
    GomokuPhase.selection => playerForColor(Side.white),
    _ => playerForColor(_turn),
  };
  bool get canPass =>
      variant.competitive && !gameOver && phase == GomokuPhase.normal;
  String get phaseLabel => switch (phase) {
    GomokuPhase.opening => '指定开局 · 由开局执黑者摆第${_moves.length + 1}子',
    GomokuPhase.exchange => '三手交换 · 开局执白者选择是否交换',
    GomokuPhase.fourth => '第四手 · 白方落子',
    GomokuPhase.declaration => '五手打点数 · 白方声明1–8个候选点',
    GomokuPhase.secondExchange => '第二次交换 · 黑方选择是否交换（五手$proposalCount打）',
    GomokuPhase.proposals =>
      '五手$proposalCount打 · 黑方给出第${_proposals.length + 1}个候选点',
    GomokuPhase.selection => '五手$proposalCount打 · 白方选择保留一个黑5',
    GomokuPhase.normal => '${_turn.label}落子',
  };
  String get phaseHint => switch (phase) {
    GomokuPhase.opening => switch (_moves.length) {
      0 => '黑1落在天元。前三子均由开局执黑者摆放。',
      1 => '摆白2：落在中心3×3区域的空点。',
      _ => '摆黑3：落在中心5×5区域的空点。',
    },
    GomokuPhase.exchange => '选择交换将互换执棋颜色；接下来由白方下第四子。',
    GomokuPhase.declaration => '白方已下第四子。声明候选数量后，当前黑方有一次交换机会。8是上限，可选择1–8。',
    GomokuPhase.secondExchange => '已知白4和候选数量，再决定是否交换；最终黑方给出候选点，白方挑选。',
    GomokuPhase.proposals => '给出$proposalCount个互不重复且不同形的合法黑5候选点，候选点不计入正式棋步。',
    GomokuPhase.selection => '点击候选点预览，再次确认保留；其余候选点移除，白方继续下第六子。',
    _ => '黑方禁长连、四四、三三；五连优先获胜。',
  };
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
      : _forbiddenLoss != null
      ? '白方获胜 · ${_forbiddenLoss!.label}判负'
      : '${_winner!.label}${resigned ? '中盘胜' : '获胜'}';
  String get turnLabel => _gameOver ? resultLabel : '${_turn.label}落子';

  GomokuMoveAnalysis _analyze(Cell cell) {
    GomokuMoveAnalysis reject(String reason) =>
        GomokuMoveAnalysis(legal: false, reason: reason);
    if (_gameOver) return reject('对局已结束');
    if (!inside(cell)) return reject('落子超出棋盘');
    if (awaitingExchange) return reject('请先选择是否交换执棋');
    if (phase == GomokuPhase.declaration) return reject('请先声明五手候选数量');
    if (phase == GomokuPhase.selection) {
      return _proposals.contains(cell)
          ? const GomokuMoveAnalysis(legal: true)
          : reject('请从黑5候选点中选择');
    }
    if (pieceAt(cell) != null) return reject('该位置已有棋子');
    if (phase == GomokuPhase.opening) {
      final radius = _moves.length;
      if ((cell.row - 7).abs() > radius || (cell.col - 7).abs() > radius) {
        return reject(
          radius == 0
              ? '黑1必须落在天元'
              : '第${radius + 1}子必须落在中心${radius * 2 + 1}×${radius * 2 + 1}区域',
        );
      }
    }
    if (phase == GomokuPhase.proposals &&
        _proposals.any(
          (other) => gomokuEquivalentProposals(board, other, cell),
        )) {
      return reject('黑5候选点不能重复或同形');
    }
    final result = analyzeGomokuMove(_board, cell, _turn, variant: variant);
    // The app adjudicates a committed forbidden black move immediately. Search
    // still uses the pure analyzer and therefore never selects a forbidden move.
    if (variant.competitive &&
        phase == GomokuPhase.normal &&
        result.forbidden != null) {
      return GomokuMoveAnalysis(legal: true, forbidden: result.forbidden);
    }
    return result;
  }

  bool canPlace(Cell cell) => _analyze(cell).legal;
  String? rejectionReason(Cell cell) => _analyze(cell).reason;

  bool place(Cell cell) {
    final analysis = _analyze(cell);
    if (!analysis.legal) return false;
    final actingPlayer = actor;
    if (phase == GomokuPhase.proposals) {
      _proposals.add(cell);
      _actions.add((actingPlayer, GomokuAction.place(cell)));
      _revision++;
      return true;
    }
    if (phase == GomokuPhase.selection) _proposals.clear();
    final side = _turn;
    _board[cell.row * size + cell.col] = side;
    _moves.add(GomokuMove(cell, side));
    if (variant.competitive) {
      _actions.add((actingPlayer, GomokuAction.place(cell)));
    }
    _turn = side.opponent;
    _passes = 0;
    _winningLine = List.of(analysis.winningLine);
    if (analysis.forbidden != null && variant.competitive) {
      _forbiddenLoss = analysis.forbidden;
      _winner = Side.white;
      _gameOver = true;
    } else if (_winningLine.isNotEmpty) {
      _winner = side;
      _gameOver = true;
    } else if (_moves.length == size * size) {
      _gameOver = true;
    }
    _revision++;
    return true;
  }

  bool exchangeColors(bool exchange) {
    if (gameOver || !awaitingExchange) return false;
    final actingPlayer = actor;
    if (phase == GomokuPhase.exchange) {
      _exchangeDecided = true;
    } else {
      _secondExchangeDecided = true;
    }
    if (exchange) _exchanged = !_exchanged;
    _actions.add((actingPlayer, GomokuAction.exchange(exchange)));
    _revision++;
    return true;
  }

  bool declareProposals(int count) {
    if (gameOver ||
        phase != GomokuPhase.declaration ||
        count < 1 ||
        count > 8) {
      return false;
    }
    _actions.add((actor, GomokuAction.declare(count)));
    _declaredProposals = count;
    _revision++;
    return true;
  }

  bool pass() {
    if (!canPass) return false;
    _actions.add((actor, const GomokuAction.pass()));
    _turn = _turn.opponent;
    _passes++;
    if (_passes == 2) _gameOver = true;
    _revision++;
    return true;
  }

  bool applyAction(GomokuAction action) => switch (action.type) {
    GomokuActionType.place => place(action.cell!),
    GomokuActionType.exchange => exchangeColors(action.exchange!),
    GomokuActionType.declare => declareProposals(action.count!),
    GomokuActionType.pass => pass(),
  };

  /// Resignation can be withdrawn without also removing the preceding stone.
  bool undo() {
    if (_resignedSide != null) {
      _resignedSide = null;
    } else if (variant.competitive) {
      if (_actions.isEmpty) return false;
      final remaining = List.of(_actions)..removeLast();
      final revision = _revision;
      reset();
      for (final (_, action) in remaining) {
        applyAction(action);
      }
      _revision = revision + 1;
      return true;
    } else {
      if (_moves.isEmpty) return false;
      final move = _moves.removeLast();
      _board[move.cell.row * size + move.cell.col] = null;
      _turn = move.side;
    }
    _gameOver = false;
    _winner = null;
    _winningLine = [];
    _forbiddenLoss = null;
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
    _exchangeDecided = false;
    _secondExchangeDecided = false;
    _declaredProposals = null;
    _exchanged = false;
    _proposals.clear();
    _actions.clear();
    _passes = 0;
    _forbiddenLoss = null;
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
    copy._exchangeDecided = _exchangeDecided;
    copy._secondExchangeDecided = _secondExchangeDecided;
    copy._declaredProposals = _declaredProposals;
    copy._exchanged = _exchanged;
    copy._proposals.addAll(_proposals);
    copy._actions.addAll(_actions);
    copy._passes = _passes;
    copy._forbiddenLoss = _forbiddenLoss;
    return copy;
  }

  Map<String, Object?> toJson() => {
    'version': variant == GomokuVariant.soosyrv8
        ? gomokuRulesVersion
        : variant.competitive
        ? 3
        : 2,
    'variant': variant.name,
    'size': size,
    'moves': _moves.map((move) => move.toJson()).toList(),
    'turn': _turn.name,
    'gameOver': _gameOver,
    'winner': _winner?.name,
    'resigned': resigned,
    'resignedSide': _resignedSide?.name,
    'revision': _revision,
    if (variant.competitive)
      'actions': [
        for (final (player, action) in _actions)
          {'player': player.name, ...action.toJson()},
      ],
  };

  /// Treat imported/network state as an untrusted move record. Replaying every
  /// move rejects illegal turn order, duplicate cells and play after a result.
  factory GomokuSession.fromJson(Object? json) {
    if (json is! Map ||
        json['version'] is! int ||
        ![1, 2, 3, gomokuRulesVersion].contains(json['version']) ||
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
    } else if ([2, 3, gomokuRulesVersion].contains(json['version'])) {
      variant = GomokuVariant.fromName(json['variant']);
    } else {
      throw const FormatException('旧版五子棋棋谱不能包含规则字段');
    }
    final session = GomokuSession(variant: variant);
    final expectedVersion = variant == GomokuVariant.soosyrv8
        ? gomokuRulesVersion
        : variant.competitive
        ? 3
        : json['version'] == 1
        ? 1
        : 2;
    if (expectedVersion != json['version']) {
      throw const FormatException('五子棋规则与棋谱版本不一致');
    }
    final records = json['moves'] as List;
    if (records.length > boardSize * boardSize) {
      throw const FormatException('五子棋棋谱落子过多');
    }
    if (variant.competitive) {
      final actions = json['actions'];
      if (actions is! List || actions.length > 1000) {
        throw const FormatException('无效的竞技连珠操作记录');
      }
      for (final raw in actions) {
        if (raw is! Map ||
            raw['player'] != session.actor.name ||
            !session.applyAction(GomokuAction.fromJson(raw))) {
          throw const FormatException('竞技连珠棋谱包含非法操作');
        }
      }
      if (records.length != session._moves.length) {
        throw const FormatException('竞技连珠棋步与操作记录不一致');
      }
      for (var i = 0; i < records.length; i++) {
        final record = records[i], move = session._moves[i];
        if (record is! Map ||
            record['row'] != move.cell.row ||
            record['col'] != move.cell.col ||
            record['side'] != move.side.name) {
          throw const FormatException('竞技连珠棋步与操作记录不一致');
        }
      }
    } else {
      for (final record in records) {
        if (record is! Map ||
            record['row'] is! int ||
            record['col'] is! int ||
            record['side'] != session.turn.name ||
            !session.place(Cell(record['row'] as int, record['col'] as int))) {
          throw const FormatException('五子棋棋谱包含非法落子');
        }
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
