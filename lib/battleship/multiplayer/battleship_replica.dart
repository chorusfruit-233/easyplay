import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../lan/message_transport.dart';
import '../battleship.dart';
import 'battleship_protocol.dart';

/// One authenticated private view. Snapshots are validated before replacement.
class BattleshipReplica extends ChangeNotifier {
  BattleshipPlayerView? view;
  List<Map<String, Object?>> seats = [];
  List<int> rematch = [];
  int seq = 0, round = 0;
  String? roomId, error, _resume;
  BattleshipSeat? _seat;
  bool connected = false, started = false;
  bool _closed = false, _preserveError = false;
  int _requestId = 0, _binding = 0;
  MessageTransport? _transport;
  StreamSubscription<LanMessage>? _messages;
  StreamSubscription<void>? _lost;
  Timer? _heartbeat;
  Future<void> Function()? reconnect;
  @visibleForTesting
  void Function(String)? onWireMessage;

  Future<void> bind(MessageTransport transport, {required String token}) async {
    if (_closed) throw StateError('房间已关闭');
    final binding = ++_binding;
    _heartbeat?.cancel();
    await _messages?.cancel();
    await _lost?.cancel();
    await _transport?.close();
    if (_closed || binding != _binding) {
      await transport.close();
      throw StateError('连接已被替换');
    }
    _transport = transport;
    connected = false;
    _preserveError = false;
    final ready = Completer<void>();
    var welcomed = false;
    var lastReceived = DateTime.now();
    HelloRetry? retry;
    unawaited(ready.future.then<void>((_) {}, onError: (Object _) {}));
    bool current() => !_closed && binding == _binding;
    _messages = transport.messages.listen(
      (message) {
        if (!current()) return;
        lastReceived = DateTime.now();
        try {
          onWireMessage?.call(message.encode());
          if (message.type != LanMessageType.battleship) {
            throw const FormatException('协议不匹配');
          }
          final payload = battleshipPayload(message);
          switch (message.body['action']) {
            case 'welcome':
              final assigned = payload['seat'];
              final nextRoom = payload['roomId'];
              final resume = payload['resume'];
              final lastRequest = payload['lastRequest'];
              if (assigned is! int ||
                  assigned < 0 ||
                  assigned > 1 ||
                  _seat != null && assigned != _seat!.index ||
                  nextRoom is! String ||
                  !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(nextRoom) ||
                  roomId != null && roomId != nextRoom ||
                  resume is! String ||
                  !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(resume) ||
                  lastRequest is! int ||
                  lastRequest < 0 ||
                  lastRequest > 1000000) {
                throw const FormatException('座位身份无效');
              }
              _seat = BattleshipSeat.values[assigned];
              roomId = nextRoom;
              _resume = resume;
              if (lastRequest > _requestId) _requestId = lastRequest;
              welcomed = true;
              retry?.cancel();
            case 'snapshot':
              if (!welcomed ||
                  payload['roomId'] != roomId ||
                  message.seq < seq) {
                return;
              }
              final next = BattleshipPlayerView.fromWire(
                Map<String, Object?>.from(payload['view'] as Map),
              );
              final nextStarted = payload['started'];
              final nextRound = payload['round'];
              final rawSeats = payload['seats'];
              final rawRematch = payload['rematch'];
              if (next.seat != _seat ||
                  nextStarted is! bool ||
                  nextRound is! int ||
                  nextRound < round ||
                  nextRound > 10000 ||
                  rawSeats is! List ||
                  rawSeats.length != 2 ||
                  rawRematch is! List ||
                  rawRematch.toSet().length != rawRematch.length ||
                  rawRematch.any((s) => s is! int || s < 0 || s > 1) ||
                  !nextStarted && next.phase != BattleshipPhase.placement ||
                  started && !nextStarted) {
                throw const FormatException('房间快照无效');
              }
              final nextSeats = <Map<String, Object?>>[];
              for (final seat in rawSeats) {
                if (seat is! Map ||
                    seat.length != 2 ||
                    seat['occupied'] is! bool ||
                    seat['connected'] is! bool ||
                    seat['connected'] == true && seat['occupied'] != true) {
                  throw const FormatException('座位快照无效');
                }
                nextSeats.add(
                  Map<String, Object?>.unmodifiable(
                    Map<String, Object?>.from(seat),
                  ),
                );
              }
              // No partially decoded fleet, turn, or room status can escape.
              view = next;
              seq = message.seq;
              round = nextRound;
              started = nextStarted;
              seats = List.unmodifiable(nextSeats);
              rematch = List.unmodifiable(rawRematch.cast<int>());
              connected = true;
              if (!_preserveError) error = null;
              if (!ready.isCompleted) ready.complete();
            case 'rejected':
              final reason = payload['reason'];
              if (reason is! String || reason.length > 512) {
                throw const FormatException('错误消息无效');
              }
              _preserveError = true;
              error = reason;
              if (!ready.isCompleted) ready.completeError(StateError(reason));
              if (welcomed) {
                transport.send(
                  battleshipMessage('sync', seq, {'roomId': roomId}),
                );
              }
            case 'ping':
              if (welcomed) {
                transport.send(
                  battleshipMessage('pong', seq, {'roomId': roomId}),
                );
              }
              return;
            default:
              throw const FormatException('未知的房间消息');
          }
          if (current()) notifyListeners();
        } catch (_) {
          connected = false;
          error = '同步失败，请重新连接';
          if (!ready.isCompleted) ready.completeError(StateError(error!));
          if (current()) notifyListeners();
          unawaited(transport.close());
        }
      },
      onError: (Object _) {
        if (!current()) return;
        connected = false;
        error = '连接消息无效';
        if (!ready.isCompleted) ready.completeError(StateError(error!));
        notifyListeners();
        unawaited(transport.close());
      },
    );
    _lost = transport.disconnections.listen((_) {
      if (!current()) return;
      connected = false;
      error = '连接中断，请重新连接';
      if (!ready.isCompleted) ready.completeError(StateError(error!));
      notifyListeners();
    });
    final hello = battleshipMessage('hello', 0, {
      'token': token,
      if (_resume != null) 'resume': _resume,
      if (roomId != null) 'roomId': roomId,
    });
    try {
      transport.send(hello);
      retry = HelloRetry(
        transport,
        hello,
        pending: () => current() && !ready.isCompleted && !welcomed,
        onError: (error) {
          if (!ready.isCompleted) ready.completeError(error);
        },
      );
      await ready.future.timeout(const Duration(seconds: 10));
      if (current()) {
        _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
          if (!current()) return;
          if (DateTime.now().difference(lastReceived) >
              const Duration(seconds: 20)) {
            _heartbeat?.cancel();
            connected = false;
            error = '连接超时，请重新连接';
            notifyListeners();
            unawaited(transport.close());
          }
        });
      }
    } catch (_) {
      await transport.close();
      rethrow;
    } finally {
      retry?.cancel();
    }
  }

  void send(String action, [Map<String, Object?> payload = const {}]) {
    if (_closed || !connected || _transport == null) throw StateError('连接中断');
    error = null;
    _preserveError = false;
    _transport!.send(
      battleshipMessage(action, seq + 1, {
        ...payload,
        'roomId': roomId,
        'round': round,
        'requestId': ++_requestId,
      }),
    );
  }

  Future<void> waitForSnapshot(
    bool Function(BattleshipReplica) predicate,
  ) async {
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
    if (_closed) return;
    error = message;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _heartbeat?.cancel();
    await _transport?.close();
    connected = false;
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _binding++;
    _heartbeat?.cancel();
    await _messages?.cancel();
    await _lost?.cancel();
    await _transport?.close();
    _resume = null;
    _seat = null;
    roomId = null;
    view = null;
    seats = [];
    rematch = [];
    super.dispose();
  }
}
