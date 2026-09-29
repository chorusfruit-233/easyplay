import '../chess/chess.dart';
import 'lan_protocol.dart';

class ChessNegotiation {
  const ChessNegotiation(this.seq, this.side);
  final int seq;
  final Side side;
}

/// Host-owned Chess state. LAN requests contain one complete move path;
/// every move is validated by the same rules engine used by local games.
class ChessAuthority {
  ChessAuthority() : _state = _ChessLanState();

  final _ChessLanState _state;
  final List<LanMessage> _events = [];
  int get seq => _events.length;
  ChessSession get session => _state.session;
  ChessNegotiation? get undoRequest => _state.undoRequest;
  ChessNegotiation? get drawRequest => _state.drawRequest;

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

  void dispose() {
    session.dispose();
    _events.clear();
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
      'game': 'chess',
      'rulesVersion': chessRulesVersion,
      'events': _events.map((event) => event.toWire()).toList(),
    });
  }
}

class ChessLanReplica {
  ChessLanReplica() : _state = _ChessLanState();

  _ChessLanState _state;
  int _seq = 0;
  int get seq => _seq;
  ChessSession get session => _state.session;
  ChessNegotiation? get undoRequest => _state.undoRequest;
  ChessNegotiation? get drawRequest => _state.drawRequest;

  bool receive(LanMessage event) {
    if (event.type == LanMessageType.stateSync) {
      if (event.seq < seq ||
          event.body['game'] != 'chess' ||
          event.body['rulesVersion'] != chessRulesVersion) {
        return false;
      }
      final events = event.body['events'];
      if (events is! List || events.length != event.seq) return false;
      final candidate = _ChessLanState();
      var replayed = 0;
      for (final raw in events) {
        if (raw is! Map<String, dynamic>) return false;
        final message = LanMessage.fromWire(raw.cast<String, Object?>());
        if (message.seq != ++replayed || candidate.apply(message) != null) {
          return false;
        }
      }
      _state.session.dispose();
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

  void dispose() => session.dispose();

  LanMessage stateRequest() =>
      LanMessage(LanMessageType.stateRequest, seq, {'lastSeq': seq});
}

class _ChessLanState {
  _ChessLanState() : session = ChessSession();

  final ChessSession session;
  ChessNegotiation? undoRequest;
  ChessNegotiation? drawRequest;

  String? apply(LanMessage event) {
    final side = event.side;
    final data = event.body;
    switch (event.type) {
      case LanMessageType.move:
        if (session.gameOver) return '对局已经结束';
        if (undoRequest != null || drawRequest != null) return '请先处理待确认请求';
        if (session.turn != side) return '尚未轮到你落子';
        final rawMove = data['move'];
        if (rawMove is! String) return '缺少 UCI 着法';
        final move = parseUciMove(rawMove);
        if (!session.applyMove(move)) return '着法不合法';
      case LanMessageType.drawClaim:
        if (undoRequest != null || drawRequest != null) return '请先处理待确认请求';
        if (session.turn != side) return '只能在自己的回合申请和棋';
        final intended = data['move'];
        if (!session.claimDraw(
          intended == null ? null : parseUciMove(intended as String),
        )) {
          return '不满足和棋条件';
        }
      case LanMessageType.resign:
        if (session.gameOver) return '对局已经结束';
        if (undoRequest != null || drawRequest != null) return '请先处理待确认请求';
        session.resign(side);
      case LanMessageType.undoRequest:
        if (session.gameOver) return '对局已经结束';
        if (undoRequest != null || drawRequest != null) return '已有待处理请求';
        if (session.moves.isEmpty) return '没有可以悔回的着手';
        undoRequest = ChessNegotiation(event.seq, side);
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
        drawRequest = ChessNegotiation(event.seq, side);
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
      default:
        return '不是国际象棋联机操作';
    }
    return null;
  }
}
