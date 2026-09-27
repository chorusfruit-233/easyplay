import '../game_session.dart';
import '../go_record.dart';
import 'lan_protocol.dart';

class LanNegotiation {
  LanNegotiation(this.seq, this.side, [Set<Cell> dead = const {}])
    : deadStones = Set.unmodifiable(dead);
  final int seq;
  final Side side;
  final Set<Cell> deadStones;
}

/// No transport or engine dependency. The host binds an authenticated socket
/// to a Side, then calls submit; a caller-supplied side never grants authority.
class LanAuthority {
  LanAuthority(GoConfig config) : _state = _LanState(config);
  final _LanState _state;
  final List<LanMessage> _events = [];
  int get seq => _events.length;
  GameSession get session => _state.snapshot();
  String get sgf => _state.record.exportSgf();
  LanNegotiation? get undoRequest => _state.undoRequest;
  LanNegotiation? get scoreProposal => _state.scoreProposal;
  bool get allowsAnalysis => _state.game.goScoreConfirmed;

  LanMessage submit(Side authenticatedSide, LanMessage request) {
    String? reason;
    if (!LanMessage.eventTypes.contains(request.type)) {
      reason = '不是对局操作';
    } else if (request.seq != seq + 1) {
      reason = '序列号不一致，请同步局面';
    } else if (request.side != authenticatedSide) {
      reason = '不能代替对手操作';
    } else {
      reason = _state.apply(request);
    }
    if (reason != null) {
      return LanMessage(LanMessageType.rejected, seq, {'reason': reason});
    }
    _events.add(request);
    return request;
  }

  /// The host may broadcast only committed events. A rejected request has no
  /// sequence number and therefore cannot advance either replica.

  /// Timeout belongs to the host clock, never the remote client's clock.
  /// The transport invokes this after its 30-second deadline. A request id
  /// prevents an old timer from cancelling a later negotiation.
  LanMessage? expireUndo(int requestSeq) {
    final pending = undoRequest;
    if (pending == null || pending.seq != requestSeq) return null;
    return submit(
      pending.side.opponent,
      LanMessage(LanMessageType.undoReject, seq + 1, {
        'side': LanMessage.sideCode(pending.side.opponent),
        'requestSeq': requestSeq,
        'reason': '对方没有回应，悔棋请求已取消',
      }),
    );
  }

  /// Full log v1 deliberately trades a small payload for correct restoration
  /// of branches, rejected negotiations, scoring and the active cursor.
  LanMessage sync(LanMessage request) {
    if (request.type != LanMessageType.stateRequest ||
        request.body['lastSeq']! as int > seq) {
      throw const FormatException('无效的同步请求');
    }
    return LanMessage(LanMessageType.stateSync, seq, {
      'roomVersion': lanProtocolVersion,
      ...LanMessage.configToWire(_state.config),
      'events': _events.map((event) => event.toWire()).toList(),
    });
  }
}

/// Receives only messages delivered by the authenticated authority transport.
/// Gaps/duplicates never change local state; caller requests stateSync on gaps.
class LanReplica {
  LanReplica(GoConfig config) : _state = _LanState(config);
  late _LanState _state;
  int _seq = 0;
  int get seq => _seq;
  GameSession get session => _state.snapshot();
  String get sgf => _state.record.exportSgf();
  LanNegotiation? get undoRequest => _state.undoRequest;
  LanNegotiation? get scoreProposal => _state.scoreProposal;
  bool get allowsAnalysis => _state.game.goScoreConfirmed;

  bool receive(LanMessage event) {
    if (event.type == LanMessageType.stateSync) {
      if (event.seq < seq) return false;
      final body = event.body;
      if (body['roomVersion'] != lanProtocolVersion) return false;
      final config = LanMessage.parseConfig(body);
      if (config.boardSize != _state.config.boardSize ||
          config.rules != _state.config.rules ||
          config.komi != _state.config.komi ||
          config.handicap != _state.config.handicap) {
        return false;
      }
      final candidate = _LanState(config);
      for (final raw in body['events']! as List) {
        final message = LanMessage.fromWire(
          (raw as Map).cast<String, Object?>(),
        );
        if (candidate.apply(message) != null) return false;
      }
      _state = candidate;
      _seq = event.seq;
      return true;
    }
    if (!LanMessage.eventTypes.contains(event.type) || event.seq != seq + 1) {
      return false;
    }
    if (_state.apply(event) != null) return false;
    _seq = event.seq;
    return true;
  }

  LanMessage stateRequest() =>
      LanMessage(LanMessageType.stateRequest, seq, {'lastSeq': seq});
}

class _LanState {
  _LanState(this.config)
    : game = GameSession(GameType.go, goConfig: config),
      record = GoSgfController(config: config);

  final GoConfig config;
  GameSession game;
  final GoSgfController record;
  LanNegotiation? undoRequest;
  LanNegotiation? scoreProposal;

  GameSession snapshot() => record.replayCurrentPath();

  String? apply(LanMessage event) {
    final side = event.side;
    final data = event.body;
    if (game.goScoreConfirmed) return '对局已经结束';
    switch (event.type) {
      case LanMessageType.move:
      case LanMessageType.pass:
        if (game.gameOver) return '正在协商计分';
        if (undoRequest != null) return '请先处理悔棋请求';
        if (game.turn != side) return '尚未轮到你落子';
        if (event.type == LanMessageType.move) {
          final cell = LanMessage.parseCell(data['cell']);
          if (!game.inside(cell)) return '坐标超出棋盘';
          if (game.pieceAt(cell) != null) return '该点已有棋子';
          if (!game.placeGo(cell)) return '自杀或劫争禁着点';
        } else {
          game.passGo();
        }
        record.appendMove(game.moves.last);
      case LanMessageType.resign:
        if (game.gameOver) return '正在协商计分';
        game.resignGo(side);
        record.appendResignation(side);
        undoRequest = null;
        scoreProposal = null;
      case LanMessageType.undoRequest:
        if (undoRequest != null || scoreProposal != null) return '已有待处理的协商';
        if (game.moves.isEmpty) return '没有可以悔回的着手';
        undoRequest = LanNegotiation(event.seq, side);
      case LanMessageType.undoAccept:
      case LanMessageType.undoReject:
        final pending = undoRequest;
        if (pending == null ||
            pending.seq != data['requestSeq'] ||
            pending.side == side) {
          return '悔棋请求已失效或不能自行同意';
        }
        if (event.type == LanMessageType.undoAccept) {
          // Protocol v1 always withdraws exactly the most recent move.
          game.undo();
          record.navigateParent();
        }
        undoRequest = null;
      case LanMessageType.scoreProposal:
      case LanMessageType.scoreCounter:
        if (!game.gameOver || game.goResignedSide != null) return '尚未进入计分';
        if (undoRequest != null) return '请先处理悔棋请求';
        final pending = scoreProposal;
        if (event.type == LanMessageType.scoreCounter) {
          if (pending == null ||
              pending.side == side ||
              pending.seq != data['requestSeq']) {
            return '计分提议已失效';
          }
        } else if (pending != null) {
          return '请回应当前计分提议';
        }
        final cells = (data['deadStones']! as List)
            .map(LanMessage.parseCell)
            .toSet();
        if (cells.any(
          (cell) => !game.inside(cell) || game.pieceAt(cell) == null,
        )) {
          return '死子必须是棋盘上现有的棋子';
        }
        // Mark whole connected groups, matching the local scoring UI.
        final expanded = <Cell>{...cells};
        final frontier = cells.toList();
        for (var i = 0; i < frontier.length; i++) {
          final cell = frontier[i];
          for (final next in [
            Cell(cell.row - 1, cell.col),
            Cell(cell.row + 1, cell.col),
            Cell(cell.row, cell.col - 1),
            Cell(cell.row, cell.col + 1),
          ]) {
            if (game.pieceAt(next)?.side == game.pieceAt(cell)?.side &&
                expanded.add(next)) {
              frontier.add(next);
            }
          }
        }
        scoreProposal = LanNegotiation(event.seq, side, expanded);
      case LanMessageType.scoreAccept:
        final proposal = scoreProposal;
        if (proposal == null ||
            proposal.seq != data['requestSeq'] ||
            proposal.side == side) {
          return '计分提议已失效或不能自行同意';
        }
        game.deadGoStones.addAll(proposal.deadStones);
        game.confirmGoScore();
        record.current.properties['XDS'] =
            proposal.deadStones.map(_coordinate).toList()..sort();
        record.current.properties['XSC'] = ['1'];
        final score = game.calculateGoScore();
        record.root.properties['RE'] = [
          score.winner == null
              ? '0'
              : '${LanMessage.sideCode(score.winner!)}+${score.margin}',
        ];
        scoreProposal = null;
      default:
        return '不是对局操作';
    }
    return null;
  }

  static String _coordinate(Cell cell) =>
      '${String.fromCharCode(97 + cell.col)}${String.fromCharCode(97 + cell.row)}';
}
