import '../game_session.dart' show Side;
import 'lan_protocol.dart';

class LanRematchRequest {
  const LanRematchRequest(this.seq, this.side);
  final int seq;
  final Side side;
}

/// Shared by the host and replicas. A new round is part of the room's event
/// log, so reconnecting across a rematch preserves both seats and sequencing.
class LanRematch {
  int round = 1;
  LanRematchRequest? request;

  String? apply(
    LanMessage event, {
    required bool gameOver,
    required void Function() restart,
  }) {
    if (!gameOver) return '请先结束当前对局';
    switch (event.type) {
      case LanMessageType.rematchRequest:
        if (request != null) return '已有再来一局请求，请先回应';
        request = LanRematchRequest(event.seq, event.side);
      case LanMessageType.rematchAccept:
      case LanMessageType.rematchReject:
        final pending = request;
        if (pending == null ||
            pending.seq != event.body['requestSeq'] ||
            pending.side == event.side) {
          return '再来一局请求已失效或不能自行回应';
        }
        if (event.type == LanMessageType.rematchAccept) {
          restart();
          round++;
        }
        request = null;
      default:
        return '不是再来一局操作';
    }
    return null;
  }
}
