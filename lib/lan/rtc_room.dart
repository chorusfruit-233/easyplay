import 'dart:async';

import '../game_session.dart' show SideX;

import 'chess_lan_game.dart';
import 'draughts_lan_game.dart';
import 'lan_game.dart';
import 'lan_protocol.dart';
import 'lan_transport.dart';
import 'message_transport.dart';
import 'room_coordinator.dart';
import 'rtc_framing.dart';
import 'rtc_manual_signaling.dart';
import 'rtc_transport.dart';

/// Adapts RTC to the existing match widgets without owning any AI engine.
class RtcMatchClient extends LanClientConnection {
  RtcMatchClient(this.invitation) : super(invitation.goConfig) {
    if (isChess) {
      chessReplica = ChessLanReplica();
    } else if (draughtsVariant != null) {
      draughtsReplica = DraughtsLanReplica(draughtsVariant!);
    } else {
      replica = LanReplica(config);
    }
  }
  final RtcInvitation invitation;
  @override
  bool get isChess => invitation.game == 'chess';
  @override
  get draughtsVariant => invitation.variant;
  final _events = StreamController<LanMessage>.broadcast();
  final _lost = StreamController<void>.broadcast();
  MessageTransport? _transport;
  StreamSubscription<LanMessage>? _subscription;
  StreamSubscription<void>? _disconnects;
  Timer? _heartbeat;
  DateTime _lastReply = DateTime.now();
  bool _closed = false;
  Future<void> Function()? renegotiate;
  void notifyLost() {
    if (!_closed && !_lost.isClosed) _lost.add(null);
  }

  @override
  Stream<LanMessage> get messages => _events.stream;
  @override
  Stream<void> get disconnections => _lost.stream;

  Future<void> bind(MessageTransport transport, {String? token}) async {
    if (_closed) throw StateError('房间已关闭');
    await _subscription?.cancel();
    await _disconnects?.cancel();
    await _transport?.close();
    _transport = transport;
    final ready = Completer<void>();
    unawaited(ready.future.then<void>((_) {}, onError: (Object _) {}));
    _subscription = transport.messages.listen(
      (message) {
        try {
          _lastReply = DateTime.now();
          if (message.type == LanMessageType.ping) {
            transport.send(
              LanMessage(LanMessageType.pong, seq, {
                'nonce': message.body['nonce'],
              }),
            );
            return;
          }
          if (message.type == LanMessageType.pong) return;
          if (message.type == LanMessageType.helloAck) {
            side = LanMessage.parseSide(message.body['assignedSide']);
            started = message.body['started'] as bool;
          } else if (message.type == LanMessageType.matchStart) {
            started = true;
          } else if (message.type == LanMessageType.rejected &&
              !ready.isCompleted) {
            ready.completeError(StateError(message.body['reason'] as String));
          } else if (message.type == LanMessageType.stateSync ||
              LanMessage.eventTypes.contains(message.type)) {
            final accepted =
                chessReplica?.receive(message) ??
                draughtsReplica?.receive(message) ??
                replica!.receive(message);
            if (!accepted) {
              if (message.type == LanMessageType.stateSync) {
                throw const FormatException('对局同步失败');
              }
              transport.send(
                LanMessage(LanMessageType.stateRequest, seq, {'lastSeq': seq}),
              );
              return;
            }
            if (message.type == LanMessageType.stateSync &&
                !ready.isCompleted) {
              if (side == null) throw const FormatException('未绑定玩家身份');
              ready.complete();
            }
          }
          _events.add(message);
        } catch (error) {
          if (!ready.isCompleted) {
            ready.completeError(error);
          } else {
            transport.send(
              LanMessage(LanMessageType.stateRequest, seq, {'lastSeq': seq}),
            );
          }
        }
      },
      onError: (Object _) {
        transport.send(
          LanMessage(LanMessageType.stateRequest, seq, {'lastSeq': seq}),
        );
      },
    );
    _disconnects = transport.disconnections.listen((_) {
      _heartbeat?.cancel();
      _transport = null;
      if (!_lost.isClosed) _lost.add(null);
      if (!ready.isCompleted) ready.completeError(StateError('对手已断开'));
    });
    transport.send(
      LanMessage(LanMessageType.hello, 0, {
        'roomVersion': lanProtocolVersion,
        ...invitation.configuration,
        'token': token ?? invitation.token,
        if (side != null) 'resumeSide': LanMessage.sideCode(side!),
      }),
    );
    try {
      await ready.future.timeout(const Duration(seconds: 10));
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
        if (DateTime.now().difference(_lastReply) >
            const Duration(seconds: 20)) {
          unawaited(transport.close());
          _transport = null;
          if (!_lost.isClosed) _lost.add(null);
        } else {
          transport.send(
            LanMessage(LanMessageType.ping, seq, {
              'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
            }),
          );
        }
      });
    } catch (_) {
      await transport.close();
      rethrow;
    }
  }

  @override
  void send(LanMessage message) {
    if (_transport == null || _closed) {
      throw StateError('WebRTC 已断开，请交换新的邀请和回应');
    }
    _transport!.send(message);
  }

  @override
  Future<void> reconnect() async {
    if (_closed || renegotiate == null) throw StateError('房主页面已关闭，房间无法恢复');
    await renegotiate!();
  }

  @override
  Future<void> disconnect() async {
    _heartbeat?.cancel();
    await _transport?.close();
    _transport = null;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    await _subscription?.cancel();
    await _disconnects?.cancel();
    await _transport?.close();
    _transport = null;
    chessReplica?.dispose();
    await _events.close();
    await _lost.close();
  }
}

class RtcRoom {
  RtcRoom.host(this.invitation) : isHost = true {
    coordinator = RoomCoordinator(
      authority: invitation.game == 'go'
          ? LanAuthority(invitation.goConfig)
          : null,
      chessAuthority: invitation.game == 'chess' ? ChessAuthority() : null,
      draughtsAuthority: invitation.game == 'draughts'
          ? DraughtsAuthority(invitation.variant!)
          : null,
      token: rtcSecret(),
    );
    client = RtcMatchClient(invitation);
  }
  RtcRoom.guest(this.invitation) : isHost = false {
    client = RtcMatchClient(invitation);
  }
  RtcInvitation invitation;
  final bool isHost;
  RoomCoordinator? coordinator;
  late final RtcMatchClient client;
  RtcPeer? peer;
  bool _localBound = false;
  StreamSubscription<void>? _remoteDisconnect;
  Future<void> prepareHost() async {
    if (_localBound) return;
    final (server, local) = MemoryTransport.pair();
    coordinator!.attach(
      server,
      fixedSide: coordinator!.firstSide,
      credential: coordinator!.token,
      identity: 'host',
    );
    await client.bind(local, token: coordinator!.token);
    _localBound = true;
  }

  Future<void> attachPeer(MessageTransport transport) async {
    if (isHost) {
      await _remoteDisconnect?.cancel();
      _remoteDisconnect = transport.disconnections.listen(
        (_) => client.notifyLost(),
      );
      coordinator!.attach(
        transport,
        fixedSide: coordinator!.firstSide.opponent,
        credential: invitation.token,
        identity: invitation.sessionId,
      );
    } else {
      await client.bind(transport);
    }
  }

  Future<void> close() async {
    await _remoteDisconnect?.cancel();
    await client.close();
    await peer?.close();
    await coordinator?.close();
  }
}
