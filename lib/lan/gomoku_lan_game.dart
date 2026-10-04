import '../game_session.dart' show Side, SideX;
import '../gomoku/gomoku_session.dart';
import 'lan_protocol.dart';
import 'lan_rematch.dart';

class GomokuNegotiation {
  const GomokuNegotiation(this.seq, this.side);
  final int seq;
  final Side side;
}

/// The authenticated host validates every move with the local rules engine.
class GomokuLanAuthority {
  GomokuLanAuthority({this.variant = GomokuVariant.freestyle})
    : _state = _GomokuLanState(variant);
  final GomokuVariant variant;
  final _GomokuLanState _state;
  final List<LanMessage> _events = [];
  int get seq => _events.length;
  GomokuSession get session => _state.session;
  GomokuNegotiation? get undoRequest => _state.undoRequest;
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

  LanMessage sync(LanMessage request) {
    if (request.type != LanMessageType.stateRequest ||
        request.body['lastSeq']! as int > seq) {
      throw const FormatException('无效的同步请求');
    }
    return LanMessage(LanMessageType.stateSync, seq, {
      'roomVersion': lanProtocolVersion,
      'game': 'gomoku',
      ...LanMessage.gomokuConfigToWire(variant),
      'events': _events.map((event) => event.toWire()).toList(),
    });
  }
}

class GomokuLanReplica {
  GomokuLanReplica({this.variant = GomokuVariant.freestyle})
    : _state = _GomokuLanState(variant);
  final GomokuVariant variant;
  _GomokuLanState _state;
  int _seq = 0;
  int get seq => _seq;
  GomokuSession get session => _state.session;
  GomokuNegotiation? get undoRequest => _state.undoRequest;
  LanRematchRequest? get rematchRequest => _state.rematch.request;
  int get round => _state.rematch.round;
  bool canRequestUndo(Side side) => _state.canRequestUndo(side);

  bool receive(LanMessage event) {
    if (event.type == LanMessageType.stateSync) {
      final data = event.body;
      if (event.seq < seq ||
          data['roomVersion'] != lanProtocolVersion ||
          data['game'] != 'gomoku' ||
          data['boardSize'] != gomokuBoardSize ||
          data['rulesVersion'] != gomokuRulesVersion ||
          data['variant'] != variant.name) {
        return false;
      }
      final events = data['events'];
      if (events is! List || events.length != event.seq) return false;
      final candidate = _GomokuLanState(variant);
      try {
        for (var i = 0; i < events.length; i++) {
          final raw = events[i];
          if (raw is! Map<String, dynamic>) return false;
          final message = LanMessage.fromWire(raw.cast<String, Object?>());
          if (message.seq != i + 1 || candidate.apply(message) != null) {
            return false;
          }
        }
      } on FormatException {
        return false;
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

class _GomokuLanState {
  _GomokuLanState(this.variant) : session = GomokuSession(variant: variant);
  final GomokuVariant variant;
  GomokuSession session;
  final rematch = LanRematch();
  GomokuNegotiation? undoRequest;

  bool canRequestUndo(Side side) =>
      !session.gameOver &&
      session.moves.isNotEmpty &&
      session.turn != side &&
      undoRequest == null;

  String? apply(LanMessage event) {
    final side = event.side;
    final data = event.body;
    switch (event.type) {
      case LanMessageType.move:
        if (session.gameOver) return '对局已经结束';
        if (undoRequest != null) return '请先处理悔棋请求';
        if (session.turn != side) return '尚未轮到你落子';
        final cell = data['cell'];
        if (cell == null) return '缺少落子坐标';
        final coordinate = LanMessage.parseCell(cell);
        if (!session.place(coordinate)) {
          return session.rejectionReason(coordinate) ?? '该位置不能落子';
        }
      case LanMessageType.resign:
        if (session.gameOver) return '对局已经结束';
        if (undoRequest != null) return '请先处理悔棋请求';
        session.resign(side);
      case LanMessageType.undoRequest:
        if (!canRequestUndo(side)) return '只能悔自己刚走且对方尚未应手的一步';
        undoRequest = GomokuNegotiation(event.seq, side);
      case LanMessageType.undoAccept:
      case LanMessageType.undoReject:
        final pending = undoRequest;
        if (pending == null ||
            pending.seq != data['requestSeq'] ||
            pending.side == side) {
          return '悔棋请求已失效或不能自行回应';
        }
        if (event.type == LanMessageType.undoAccept && !session.undo()) {
          return '无法撤回落子';
        }
        undoRequest = null;
      case LanMessageType.rematchRequest:
      case LanMessageType.rematchAccept:
      case LanMessageType.rematchReject:
        return rematch.apply(
          event,
          gameOver: session.gameOver,
          restart: () {
            session = GomokuSession(variant: variant);
            undoRequest = null;
          },
        );
      default:
        return '不是五子棋联机操作';
    }
    return null;
  }
}
