import '../draughts/draughts.dart';
import '../game_session.dart' show Cell, Side, SideX;
import 'lan_protocol.dart';
import 'lan_rematch.dart';

class DraughtsNegotiation {
  const DraughtsNegotiation(this.seq, this.side);
  final int seq;
  final Side side;
}

/// Host-owned Draughts state. LAN requests contain one complete move path;
/// every move is validated by the same rules engine used by local games.
class DraughtsAuthority {
  DraughtsAuthority(this.variant) : _state = _DraughtsLanState(variant);

  final DraughtsVariant variant;
  final _DraughtsLanState _state;
  final List<LanMessage> _events = [];
  int get seq => _events.length;
  DraughtsSession get session => _state.session;
  DraughtsNegotiation? get undoRequest => _state.undoRequest;
  DraughtsNegotiation? get drawRequest => _state.drawRequest;
  LanRematchRequest? get rematchRequest => _state.rematch.request;
  int get round => _state.rematch.round;
  bool canRequestUndo(Side side) => _state.canRequestUndo(side);

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

  LanMessage? expireDraw(int requestSeq) {
    final pending = drawRequest;
    if (pending == null || pending.seq != requestSeq) return null;
    return submit(
      pending.side.opponent,
      LanMessage(LanMessageType.drawReject, seq + 1, {
        'side': LanMessage.sideCode(pending.side.opponent),
        'requestSeq': requestSeq,
      }),
    );
  }

  LanMessage sync(LanMessage request) {
    if (request.type != LanMessageType.stateRequest ||
        request.body['lastSeq']! as int > seq) {
      throw const FormatException('无效的同步请求');
    }
    return LanMessage(LanMessageType.stateSync, seq, {
      'roomVersion': lanProtocolVersion,
      'game': 'draughts',
      'variant': variant.name,
      'rulesVersion': draughtsRulesVersion,
      'events': _events.map((event) => event.toWire()).toList(),
    });
  }
}

class DraughtsLanReplica {
  DraughtsLanReplica(this.variant) : _state = _DraughtsLanState(variant);

  final DraughtsVariant variant;
  _DraughtsLanState _state;
  int _seq = 0;
  int get seq => _seq;
  DraughtsSession get session => _state.session;
  DraughtsNegotiation? get undoRequest => _state.undoRequest;
  DraughtsNegotiation? get drawRequest => _state.drawRequest;
  LanRematchRequest? get rematchRequest => _state.rematch.request;
  int get round => _state.rematch.round;
  bool canRequestUndo(Side side) => _state.canRequestUndo(side);

  bool receive(LanMessage event) {
    if (event.type == LanMessageType.stateSync) {
      if (event.seq < seq ||
          event.body['game'] != 'draughts' ||
          event.body['variant'] != variant.name ||
          event.body['rulesVersion'] != draughtsRulesVersion) {
        return false;
      }
      final events = event.body['events'];
      if (events is! List || events.length != event.seq) return false;
      final candidate = _DraughtsLanState(variant);
      for (final raw in events) {
        if (raw is! Map<String, dynamic>) return false;
        final message = LanMessage.fromWire(raw.cast<String, Object?>());
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

class _DraughtsLanState {
  _DraughtsLanState(this.variant)
    : session = DraughtsSession(DraughtsRules.forVariant(variant));

  final DraughtsVariant variant;
  DraughtsSession session;
  final rematch = LanRematch();
  DraughtsNegotiation? undoRequest;
  DraughtsNegotiation? drawRequest;

  bool canRequestUndo(Side side) =>
      !session.gameOver &&
      session.moves.isNotEmpty &&
      session.turn != side &&
      undoRequest == null &&
      drawRequest == null;

  String? apply(LanMessage event) {
    final side = event.side;
    final data = event.body;
    switch (event.type) {
      case LanMessageType.move:
        if (session.gameOver) return '对局已经结束';
        if (undoRequest != null || drawRequest != null) return '请先处理待确认请求';
        if (session.turn != side) return '尚未轮到你落子';
        final rawPath = data['path'];
        if (rawPath is! List) return '缺少完整着法路径';
        final path = rawPath.map((raw) {
          final cell = LanMessage.parseCell(raw);
          return Cell(cell.row, cell.col);
        }).toList();
        final move = session
            .legalMoves()
            .where(
              (candidate) =>
                  candidate.path.length == path.length &&
                  List.generate(
                    path.length,
                    (i) => candidate.path[i] == path[i],
                  ).every((v) => v),
            )
            .firstOrNull;
        if (move == null || !session.applyMove(move)) return '完整着法不合法';
      case LanMessageType.resign:
        if (session.gameOver) return '对局已经结束';
        if (undoRequest != null || drawRequest != null) return '请先处理待确认请求';
        session.resign(side);
      case LanMessageType.undoRequest:
        if (session.gameOver) return '对局已经结束';
        if (undoRequest != null || drawRequest != null) return '已有待处理请求';
        if (session.moves.isEmpty) return '没有可以悔回的着手';
        if (session.turn == side) return '只能悔自己刚走且对方尚未应手的一步';
        undoRequest = DraughtsNegotiation(event.seq, side);
      case LanMessageType.undoAccept:
      case LanMessageType.undoReject:
        final pending = undoRequest;
        if (pending == null ||
            pending.seq != data['requestSeq'] ||
            pending.side == side) {
          return '悔棋请求已失效或不能自行回应';
        }
        if (event.type == LanMessageType.undoAccept && !session.undo()) {
          return '无法撤回完整一手';
        }
        undoRequest = null;
      case LanMessageType.drawRequest:
        if (session.gameOver) return '对局已经结束';
        if (undoRequest != null || drawRequest != null) return '已有待处理请求';
        drawRequest = DraughtsNegotiation(event.seq, side);
      case LanMessageType.drawAccept:
      case LanMessageType.drawReject:
        final pending = drawRequest;
        if (pending == null ||
            pending.seq != data['requestSeq'] ||
            pending.side == side) {
          return '和棋请求已失效或不能自行回应';
        }
        if (event.type == LanMessageType.drawAccept) session.agreeDraw();
        drawRequest = null;
      case LanMessageType.rematchRequest:
      case LanMessageType.rematchAccept:
      case LanMessageType.rematchReject:
        return rematch.apply(
          event,
          gameOver: session.gameOver,
          restart: () {
            session = DraughtsSession(DraughtsRules.forVariant(variant));
            undoRequest = null;
            drawRequest = null;
          },
        );
      default:
        return '不是跳棋联机操作';
    }
    return null;
  }
}
