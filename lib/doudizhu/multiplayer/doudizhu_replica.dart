import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../lan/message_transport.dart';
import '../doudizhu.dart';
import 'card_room_protocol.dart';

/// Owns one private view; snapshots replace it atomically, never replay deltas.
class DouDizhuReplica extends ChangeNotifier {
  DouDizhuPlayerView? view;
  List<Map<String, Object?>> seats = [];
  List<int> rematch = [];
  int seq = 0;
  String? roomId, _resume;
  String? error;
  @visibleForTesting
  void Function(String)? onWireMessage;
  bool connected = false, _closed = false, _preserveError = false;
  MessageTransport? _transport;
  StreamSubscription<LanMessage>? _messages;
  StreamSubscription<void>? _lost;
  Future<void> Function()? reconnect;
  Future<void> bind(MessageTransport transport, {required String token}) async {
    if (_closed) throw StateError('房间已关闭');
    await _messages?.cancel();
    await _lost?.cancel();
    await _transport?.close();
    _transport = transport;
    _preserveError = false;
    final ready = Completer<void>();
    unawaited(ready.future.then<void>((_) {}, onError: (Object _) {}));
    _messages = transport.messages.listen(
      (m) {
        try {
          onWireMessage?.call(m.encode());
          if (m.type != LanMessageType.card) {
            throw const FormatException('协议不匹配');
          }
          final p = cardPayload(m);
          switch (m.body['action']) {
            case 'welcome':
              if (roomId != null && roomId != p['roomId']) {
                throw const FormatException('房间身份不匹配');
              }
              roomId = p['roomId'] as String;
              _resume = p['resume'] as String;
            case 'snapshot':
              if (p['roomId'] != roomId || m.seq < seq) return;
              final next = DouDizhuPlayerView.fromWire(
                Map<String, Object?>.from(p['view'] as Map),
              );
              if (view != null && view!.seat != next.seat) {
                throw const FormatException('座位身份改变');
              }
              view = next;
              seq = m.seq;
              seats = (p['seats'] as List)
                  .map((s) => Map<String, Object?>.from(s as Map))
                  .toList();
              rematch = (p['rematch'] as List).cast<int>();
              connected = true;
              if (!_preserveError) error = null;
              if (!ready.isCompleted) ready.complete();
            case 'rejected':
              _preserveError = true;
              error = p['reason'] as String;
              if (!ready.isCompleted) ready.completeError(StateError(error!));
              if (connected) {
                _transport?.send(cardMessage('sync', seq, {'roomId': roomId}));
              }
            case 'ping':
              _transport?.send(cardMessage('pong', seq, {'roomId': roomId}));
              return;
          }
          if (!_closed) notifyListeners();
        } catch (_) {
          connected = false;
          error = '同步失败，请重新连接';
          if (!ready.isCompleted) ready.completeError(StateError(error!));
          if (!_closed) notifyListeners();
          unawaited(transport.close());
        }
      },
      onError: (Object _) {
        error = '连接消息无效';
        if (!_closed) notifyListeners();
      },
    );
    _lost = transport.disconnections.listen((_) {
      connected = false;
      error = '连接中断，请重新连接';
      if (!ready.isCompleted) ready.completeError(StateError(error!));
      if (!_closed) notifyListeners();
    });
    transport.send(
      cardMessage('hello', 0, {
        'token': token,
        if (_resume != null) 'resume': _resume,
        if (roomId != null) 'roomId': roomId,
      }),
    );
    try {
      await ready.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      await transport.close();
      rethrow;
    }
  }

  void send(String action, [Map<String, Object?> payload = const {}]) {
    if (!connected || _transport == null) throw StateError('连接中断');
    error = null;
    _preserveError = false;
    _transport!.send(
      cardMessage(action, seq + 1, {'roomId': roomId, ...payload}),
    );
  }

  Future<void> waitForSnapshot(bool Function(DouDizhuReplica) predicate) async {
    if (predicate(this)) return;
    final completed = Completer<void>();
    void check() {
      if (predicate(this) && !completed.isCompleted) completed.complete();
    }

    addListener(check);
    try {
      await completed.future.timeout(const Duration(seconds: 10));
    } finally {
      if (!_closed) removeListener(check);
    }
  }

  void reportError(String message) {
    if (!_closed) {
      error = message;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _transport?.close();
    connected = false;
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _messages?.cancel();
    await _lost?.cancel();
    await _transport?.close();
    _resume = null;
    view = null;
    seats.clear();
    rematch.clear();
    super.dispose();
  }
}
