import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../lan/message_transport.dart';
import '../doudizhu.dart';
import 'card_room_protocol.dart';

String cardSecret() => base64UrlEncode(
  List.generate(32, (_) => Random.secure().nextInt(256)),
).replaceAll('=', '');

class _Seat {
  String? credential;
  bool ready = false, ai = false;
  _Connection? connection;
}

class _Connection {
  _Connection(this.transport);
  final MessageTransport transport;
  PlayerSeat? seat;
  StreamSubscription<LanMessage>? messages;
  StreamSubscription<void>? lost;
  DateTime lastSeen = DateTime.now();
}

/// A three-seat authority. Only recipient-specific snapshots leave this class.
class CardRoomCoordinator extends ChangeNotifier {
  CardRoomCoordinator({required this.password, DouDizhuSession? session})
    : session = session ?? DouDizhuSession() {
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      for (final c in _connections.toList()) {
        if (DateTime.now().difference(c.lastSeen) >
            const Duration(seconds: 20)) {
          _detach(c);
          unawaited(c.transport.close());
        } else if (c.seat != null) {
          _send(c, cardMessage('ping', seq, {}));
        }
      }
    });
  }
  final String password;
  final String roomId = cardSecret();
  final String hostCredential = cardSecret();
  final DouDizhuSession session;
  final _seats = List.generate(3, (_) => _Seat());
  final _connections = <_Connection>[];
  final _rematch = <PlayerSeat>{};
  late final Timer _heartbeat;
  int seq = 0, _generation = 0;
  bool _closed = false, _thinking = false;
  int get playerCount =>
      _seats.where((s) => s.credential != null || s.ai).length;
  bool get allConnected => _seats.every((s) => s.ai || s.connection != null);
  bool get canStart =>
      session.phase == DouDizhuPhase.waiting &&
      allConnected &&
      _seats.every((s) => s.ready);
  List<Map<String, Object?>> get seats => [
    for (final s in _seats)
      {
        'occupied': s.credential != null || s.ai,
        'connected': s.connection != null || s.ai,
        'ready': s.ready,
        'ai': s.ai,
      },
  ];
  void setAi(PlayerSeat seat, bool enabled) {
    if (_closed ||
        seat == PlayerSeat.seat0 ||
        session.phase != DouDizhuPhase.waiting ||
        _seats[seat.index].credential != null) {
      throw StateError('此座位不能设置 AI');
    }
    _seats[seat.index]
      ..ai = enabled
      ..ready = enabled;
    _changed();
  }

  void attach(
    MessageTransport transport, {
    PlayerSeat? fixedSeat,
    String? invitationCredential,
  }) {
    if (_closed) {
      unawaited(transport.close());
      return;
    }
    final c = _Connection(transport);
    _connections.add(c);
    c.messages = transport.messages.listen(
      (m) {
        c.lastSeen = DateTime.now();
        try {
          if (m.type != LanMessageType.card) throw StateError('协议不匹配');
          final p = cardPayload(m), action = m.body['action'];
          if (action == 'hello') {
            if (c.seat != null) throw StateError('身份已经绑定');
            _hello(c, p, fixedSeat, invitationCredential);
            return;
          }
          if (c.seat == null ||
              p['roomId'] != roomId ||
              !identical(_seats[c.seat!.index].connection, c)) {
            throw StateError('身份验证失败');
          }
          if (action == 'pong') return;
          if (action == 'sync') {
            _snapshot(c);
            return;
          }
          if (action == 'ready') {
            if (session.phase != DouDizhuPhase.waiting) {
              throw StateError('对局已经开始');
            }
            _seats[c.seat!.index].ready = true;
            _changed();
            return;
          }
          _submit(c.seat!, action as String, m.seq, p);
        } catch (e) {
          _send(
            c,
            cardMessage('rejected', seq, {
              'reason': e is StateError ? e.message : '请求格式无效',
            }),
          );
        }
      },
      onError: (Object _) =>
          _send(c, cardMessage('rejected', seq, {'reason': '请求格式无效'})),
    );
    c.lost = transport.disconnections.listen((_) => _detach(c));
    // Unauthenticated idle connections cannot hold resources indefinitely.
  }

  void _hello(
    _Connection c,
    Map<String, Object?> p,
    PlayerSeat? fixed,
    String? invite,
  ) {
    PlayerSeat? seat;
    if (p['resume'] is String) {
      if (p['roomId'] != roomId) throw StateError('房间身份不匹配');
      for (final s in PlayerSeat.values) {
        if (_seats[s.index].credential == p['resume']) seat = s;
      }
      if (seat == null || (fixed != null && seat != fixed)) {
        throw StateError('恢复凭据无效');
      }
      if (_seats[seat.index].connection != null) throw StateError('此座位仍然在线');
    } else {
      final valid = fixed == PlayerSeat.seat0
          ? p['token'] == hostCredential
          : p['token'] == (invite ?? password);
      if (!valid) throw StateError('房间口令无效');
      if (session.phase != DouDizhuPhase.waiting) {
        throw StateError('对局已开始，请使用原座位重连');
      }
      seat =
          fixed ??
          [PlayerSeat.seat1, PlayerSeat.seat2]
              .where(
                (s) =>
                    !_seats[s.index].ai && _seats[s.index].credential == null,
              )
              .firstOrNull;
      if (seat == null ||
          _seats[seat.index].ai ||
          _seats[seat.index].credential != null) {
        throw StateError('房间已满或座位已被占用');
      }
      _seats[seat.index].credential = cardSecret();
    }
    c.seat = seat;
    _seats[seat.index].connection = c;
    _send(
      c,
      cardMessage('welcome', seq, {
        'roomId': roomId,
        'seat': seat.index,
        'resume': _seats[seat.index].credential,
      }),
    );
    _changed();
  }

  void _submit(
    PlayerSeat seat,
    String action,
    int requestSeq,
    Map<String, Object?> p,
  ) {
    if (requestSeq != seq + 1) throw StateError('状态已更新，请同步后重试');
    if (!allConnected) throw StateError('等待离线玩家恢复连接');
    switch (action) {
      case 'start':
        if (seat != PlayerSeat.seat0 || !canStart) {
          throw StateError('三名玩家准备后由房主开始');
        }
        session.deal();
      case 'bid':
        session.bid(seat, p['score'] as int);
      case 'play':
        session.play(seat, (p['cards'] as List).cast<int>());
      case 'pass':
        session.pass(seat);
      case 'rematch':
        if (session.phase != DouDizhuPhase.finished) throw StateError('对局尚未结束');
        _rematch.add(seat);
        if (PlayerSeat.values.every(
          (s) => _seats[s.index].ai || _rematch.contains(s),
        )) {
          _rematch.clear();
          session.deal();
        }
      default:
        throw StateError('不支持的操作');
    }
    _changed();
  }

  void _send(_Connection c, LanMessage m) {
    if (_closed) return;
    try {
      c.transport.send(m);
    } catch (_) {
      _detach(c);
    }
  }

  void _snapshot(_Connection c) {
    if (c.seat == null) return;
    _send(
      c,
      cardMessage('snapshot', seq, {
        'roomId': roomId,
        'view': session.view(c.seat!).toWire(),
        'seats': seats,
        'rematch': _rematch.map((s) => s.index).toList(),
      }),
    );
  }

  void _changed() {
    if (_closed) return;
    seq++;
    _generation++;
    for (final c in _connections.toList()) {
      if (c.seat != null) _snapshot(c);
    }
    notifyListeners();
    _driveAi();
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

  Future<void> _driveAi() async {
    if (_closed ||
        _thinking ||
        !allConnected ||
        !_seats[session.turn.index].ai ||
        ![
          DouDizhuPhase.bidding,
          DouDizhuPhase.playing,
        ].contains(session.phase)) {
      return;
    }
    _thinking = true;
    final generation = _generation,
        seat = session.turn,
        view = session.view(session.turn);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final ids = view.publicState.phase == DouDizhuPhase.playing
          ? await const DouDizhuAi().chooseAsync(view)
          : <int>[];
      if (_closed || generation != _generation || !allConnected) return;
      if (view.publicState.phase == DouDizhuPhase.bidding) {
        _submit(seat, 'bid', seq + 1, {
          'score': const BiddingPolicy().choose(view),
        });
      } else {
        _submit(seat, ids.isEmpty ? 'pass' : 'play', seq + 1, {'cards': ids});
      }
    } finally {
      _thinking = false;
      if (!_closed) unawaited(_driveAi());
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _heartbeat.cancel();
    for (final c in _connections.toList()) {
      await c.messages?.cancel();
      await c.lost?.cancel();
      await c.transport.close();
    }
    _connections.clear();
    _rematch.clear();
    session.close();
    for (final s in _seats) {
      s.credential = null;
      s.connection = null;
      s.ready = false;
      s.ai = false;
    }
    super.dispose();
  }
}
