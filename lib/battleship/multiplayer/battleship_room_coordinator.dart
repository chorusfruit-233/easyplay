import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../lan/message_transport.dart';
import '../battleship.dart';
import 'battleship_protocol.dart';

String battleshipSecret() => base64UrlEncode(
  List.generate(32, (_) => Random.secure().nextInt(256)),
).replaceAll('=', '');

class _Seat {
  String? credential;
  _Connection? connection;
  int lastRequest = 0;
}

class _Connection {
  _Connection(this.transport);
  final MessageTransport transport;
  BattleshipSeat? seat;
  String? helloSignature;
  StreamSubscription<LanMessage>? messages;
  StreamSubscription<void>? lost;
  DateTime lastSeen = DateTime.now();
  int failures = 0;
}

/// Host authority; only recipient-specific views leave this class.
class BattleshipRoomCoordinator extends ChangeNotifier {
  BattleshipRoomCoordinator({
    required this.password,
    BattleshipSession? session,
  }) : session = session ?? BattleshipSession() {
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      for (final c in _connections.toList()) {
        if (c.transport is MemoryTransport) continue;
        if (DateTime.now().difference(c.lastSeen) >
            const Duration(seconds: 20)) {
          _detach(c);
          unawaited(c.transport.close());
        } else if (c.seat != null) {
          _send(c, battleshipMessage('ping', seq, {}));
        }
      }
    });
  }

  final String password;
  final String roomId = battleshipSecret();
  final String hostCredential = battleshipSecret();
  final BattleshipSession session;
  final _seats = List.generate(2, (_) => _Seat());
  final _connections = <_Connection>[];
  final _rematch = <BattleshipSeat>{};
  late final Timer _heartbeat;
  bool _closed = false;
  bool started = false;
  int seq = 0, round = 0;

  int get playerCount => _seats.where((s) => s.credential != null).length;
  bool get allConnected => _seats.every((s) => s.connection != null);
  bool get canStart => !started && allConnected;
  List<Map<String, Object?>> get seats => [
    for (final s in _seats)
      {'occupied': s.credential != null, 'connected': s.connection != null},
  ];

  /// A replacement RTC invitation disconnects only the guest's old channel.
  Future<void> disconnectSeat(BattleshipSeat seat) async {
    if (seat == BattleshipSeat.player1) throw StateError('不能断开房主座位');
    final c = _seats[seat.index].connection;
    if (c != null) {
      _detach(c);
      await c.transport.close();
    }
  }

  void attach(
    MessageTransport transport, {
    BattleshipSeat? fixedSeat,
    String? invitationCredential,
  }) {
    if (_closed || _connections.length >= 8) {
      unawaited(transport.close());
      return;
    }
    final c = _Connection(transport);
    _connections.add(c);
    c.messages = transport.messages.listen(
      (message) {
        c.lastSeen = DateTime.now();
        try {
          if (message.type != LanMessageType.battleship) {
            throw StateError('协议不匹配');
          }
          final payload = battleshipPayload(message);
          final action = message.body['action'] as String;
          if (action == 'hello') {
            if (c.seat != null) {
              if (message.encode() != c.helloSignature ||
                  !identical(_seats[c.seat!.index].connection, c)) {
                throw StateError('身份已经绑定');
              }
              _welcome(c);
              _snapshot(c);
            } else {
              _hello(
                c,
                payload,
                fixedSeat,
                invitationCredential,
                message.encode(),
              );
            }
            return;
          }
          if (c.seat == null ||
              payload['roomId'] != roomId ||
              !identical(_seats[c.seat!.index].connection, c)) {
            throw StateError('身份验证失败');
          }
          if (action == 'pong') return;
          if (action == 'sync') {
            _snapshot(c);
            return;
          }
          final request = payload['requestId'];
          if (request is! int || request < 1 || request > 1000000) {
            throw StateError('请求标识无效');
          }
          final seat = _seats[c.seat!.index];
          if (request <= seat.lastRequest) {
            _snapshot(c);
            return;
          }
          // Consume rejected identifiers too: an invalid old shot must never
          // become valid when replayed on a later turn or after reconnecting.
          seat.lastRequest = request;
          if (payload['round'] != round) throw StateError('对局已经更新，请重试');
          _submit(c.seat!, action, message.seq, payload);
        } catch (error) {
          if (c.seat == null && ++c.failures >= 3) {
            _detach(c);
            unawaited(c.transport.close());
            return;
          }
          _send(
            c,
            battleshipMessage('rejected', seq, {
              'reason': error is StateError ? error.message : '请求格式无效',
            }),
          );
        }
      },
      onError: (Object _) =>
          _send(c, battleshipMessage('rejected', seq, {'reason': '请求格式无效'})),
    );
    c.lost = transport.disconnections.listen((_) => _detach(c));
  }

  void _hello(
    _Connection c,
    Map<String, Object?> p,
    BattleshipSeat? fixed,
    String? invite,
    String signature,
  ) {
    BattleshipSeat? seat;
    if (p['resume'] is String) {
      if (p['roomId'] != roomId) throw StateError('房间身份不匹配');
      for (final candidate in BattleshipSeat.values) {
        if (_seats[candidate.index].credential == p['resume']) seat = candidate;
      }
      if (seat == null || fixed != null && seat != fixed) {
        throw StateError('恢复凭据无效');
      }
      if (_seats[seat.index].connection != null) throw StateError('此座位仍然在线');
    } else {
      final token = fixed == BattleshipSeat.player1
          ? hostCredential
          : invite ?? password;
      if (p['token'] != token) throw StateError('房间口令无效');
      if (started) throw StateError('对局已开始，请使用原座位重连');
      seat = fixed ?? BattleshipSeat.player2;
      if (_seats[seat.index].credential != null) throw StateError('座位已被占用');
      _seats[seat.index].credential = battleshipSecret();
    }
    c.seat = seat;
    c.helloSignature = signature;
    _seats[seat.index].connection = c;
    _welcome(c);
    _changed();
  }

  void _welcome(_Connection c) {
    final seat = c.seat!;
    _send(
      c,
      battleshipMessage('welcome', seq, {
        'roomId': roomId,
        'seat': seat.index,
        'resume': _seats[seat.index].credential,
        'lastRequest': _seats[seat.index].lastRequest,
      }),
    );
  }

  void _submit(
    BattleshipSeat seat,
    String action,
    int requestSeq,
    Map<String, Object?> p,
  ) {
    if (!allConnected) throw StateError('等待离线玩家恢复连接');
    final placement =
        started &&
        session.phase == BattleshipPhase.placement &&
        ['place', 'remove', 'randomize', 'clear', 'ready'].contains(action);
    final rematch =
        action == 'rematch' && session.phase == BattleshipPhase.finished;
    // Independent fleet edits can share the same public base revision. Their
    // per-seat request identifiers preserve ordering without leaking fleets.
    if (requestSeq < 1 ||
        requestSeq > seq + 1 ||
        !placement && !rematch && requestSeq != seq + 1) {
      throw StateError('状态已更新，请同步后重试');
    }
    if (action != 'start' && !started) throw StateError('请等待房主开始对局');
    switch (action) {
      case 'start':
        if (seat != BattleshipSeat.player1 || !canStart) {
          throw StateError('两位玩家连接后由房主开始');
        }
        started = true;
      case 'place':
        session.place(
          seat,
          ShipPlacement.fromWire({
            'ship': p['ship'],
            'start': p['start'],
            'direction': p['direction'],
          }),
        );
      case 'remove':
        final ship = ShipType.values
            .where((s) => s.name == p['ship'])
            .firstOrNull;
        if (ship == null) throw StateError('舰船类型无效');
        session.remove(seat, ship);
      case 'randomize':
        session.randomizeFleet(seat);
      case 'clear':
        session.clearFleet(seat);
      case 'ready':
        session.ready(seat);
      case 'fire':
        if (p['cell'] is! int) throw StateError('坐标无效');
        session.fire(seat, p['cell'] as int);
      case 'resign':
        session.resign(seat);
      case 'rematch':
        if (session.phase != BattleshipPhase.finished) {
          throw StateError('对局尚未结束');
        }
        if (!_rematch.add(seat)) return;
        if (_rematch.length == 2) {
          _rematch.clear();
          session.reset();
          round++;
        }
      default:
        throw StateError('不支持的操作');
    }
    _changed();
  }

  void _send(_Connection c, LanMessage message) {
    if (_closed) return;
    try {
      c.transport.send(message);
    } catch (_) {
      _detach(c);
    }
  }

  void _snapshot(_Connection c) {
    if (c.seat == null) return;
    _send(
      c,
      battleshipMessage('snapshot', seq, {
        'roomId': roomId,
        'started': started,
        'round': round,
        'view': session.view(c.seat!).toWire(),
        'seats': seats,
        'rematch': _rematch.map((s) => s.index).toList(),
      }),
    );
  }

  void _changed() {
    if (_closed) return;
    if (seq >= 19999) {
      unawaited(close());
      return;
    }
    seq++;
    for (final c in _connections.toList()) {
      if (c.seat != null) _snapshot(c);
    }
    notifyListeners();
  }

  void _detach(_Connection c) {
    if (!_connections.remove(c)) return;
    unawaited(c.messages?.cancel());
    unawaited(c.lost?.cancel());
    if (c.seat != null && identical(_seats[c.seat!.index].connection, c)) {
      _seats[c.seat!.index].connection = null;
      _changed();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat.cancel();
    for (final c in _connections.toList()) {
      await c.messages?.cancel();
      await c.lost?.cancel();
      await c.transport.close();
    }
    _connections.clear();
    _rematch.clear();
    for (final seat in _seats) {
      seat.credential = null;
      seat.connection = null;
    }
    super.dispose();
  }
}
