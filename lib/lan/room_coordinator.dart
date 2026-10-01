import 'dart:async';

import '../game_session.dart';
import '../chess/chess_session.dart' show chessRulesVersion;
import '../draughts/draughts_session.dart' show draughtsRulesVersion;
import 'chess_lan_game.dart';
import 'draughts_lan_game.dart';
import 'lan_game.dart';
import 'lan_protocol.dart';
import 'lan_rematch.dart';
import 'message_transport.dart';

/// Owns seats and committed events independently of sockets or WebRTC.
class RoomCoordinator {
  RoomCoordinator({
    LanAuthority? authority,
    this.draughtsAuthority,
    this.chessAuthority,
    required this.token,
  })
    // Preserve the named constructor parameter used by LAN callers.
    // ignore: prefer_initializing_formals
    : _authority = authority {
    if ([
          _authority,
          draughtsAuthority,
          chessAuthority,
        ].where((a) => a != null).length !=
        1) {
      throw ArgumentError('provide exactly one game authority');
    }
  }
  final LanAuthority? _authority;
  LanAuthority get authority => _authority!;
  final DraughtsAuthority? draughtsAuthority;
  final ChessAuthority? chessAuthority;
  final String token;
  bool _started = false;
  bool _closed = false;
  final _clients = <_RoomPeer>[];
  final _authFailures = <String, List<DateTime>>{};
  final _playerCounts = StreamController<int>.broadcast();
  Timer? _undoTimer;
  bool get started => _started;
  bool get isDraughts => draughtsAuthority != null;
  int get playerCount => _clients.where((peer) => peer.side != null).length;
  Stream<int> get playerCounts => _playerCounts.stream;
  int get seq => chessAuthority?.seq ?? draughtsAuthority?.seq ?? authority.seq;
  bool get gameOver =>
      chessAuthority?.session.gameOver ??
      draughtsAuthority?.session.gameOver ??
      authority.session.gameOver;
  Side get firstSide => chessAuthority != null
      ? Side.white
      : draughtsAuthority?.session.rules.firstMove ?? Side.black;
  LanRematchRequest? get _rematchRequest =>
      chessAuthority?.rematchRequest ??
      draughtsAuthority?.rematchRequest ??
      _authority?.rematchRequest;

  void attach(
    MessageTransport transport, {
    String identity = 'local',
    Side? fixedSide,
    String? credential,
  }) {
    if (_closed) throw StateError('房间已关闭');
    final peer = _RoomPeer(this, transport, identity, fixedSide, credential);
    _clients.add(peer);
    peer.listen();
  }

  void startMatch() {
    if (_started) return;
    if (playerCount != 2) throw StateError('对手尚未加入');
    _started = true;
    _broadcast(LanMessage(LanMessageType.matchStart, seq));
  }

  void _remove(_RoomPeer peer) {
    if (_clients.remove(peer)) {
      if (peer.side != null && !_playerCounts.isClosed) {
        _playerCounts.add(playerCount);
      }
      unawaited(peer.close());
    }
  }

  bool _tooManyFailures(String address) {
    final recent = _authFailures.putIfAbsent(address, () => []);
    recent.removeWhere(
      (at) => DateTime.now().difference(at) > const Duration(minutes: 1),
    );
    return recent.length >= 5;
  }

  void _recordAuthFailure(String address) =>
      _authFailures.putIfAbsent(address, () => []).add(DateTime.now());

  void _broadcast(LanMessage event) {
    if (event.type == LanMessageType.undoRequest) {
      _undoTimer?.cancel();
      _undoTimer = Timer(const Duration(seconds: 30), () {
        final expired = chessAuthority != null
            ? chessAuthority!.expireUndo(event.seq)
            : draughtsAuthority != null
            ? draughtsAuthority!.expireUndo(event.seq)
            : authority.expireUndo(event.seq);
        if (expired != null) _broadcast(expired);
      });
    } else if (event.type == LanMessageType.drawRequest) {
      _undoTimer?.cancel();
      _undoTimer = Timer(const Duration(seconds: 30), () {
        final expired =
            chessAuthority?.expireDraw(event.seq) ??
            draughtsAuthority?.expireDraw(event.seq);
        if (expired != null) _broadcast(expired);
      });
    } else if (event.type == LanMessageType.rematchRequest) {
      _undoTimer?.cancel();
      _undoTimer = Timer(const Duration(seconds: 30), () {
        final pending = _rematchRequest;
        if (pending == null || pending.seq != event.seq) return;
        final expired = submit(
          pending.side.opponent,
          LanMessage(LanMessageType.rematchReject, seq + 1, {
            'side': LanMessage.sideCode(pending.side.opponent),
            'requestSeq': pending.seq,
          }),
        );
        if (expired.type != LanMessageType.rejected) _broadcast(expired);
      });
    } else if (event.type == LanMessageType.rematchAccept ||
        event.type == LanMessageType.rematchReject ||
        event.type == LanMessageType.undoAccept ||
        event.type == LanMessageType.undoReject ||
        event.type == LanMessageType.drawAccept ||
        event.type == LanMessageType.drawReject) {
      _undoTimer?.cancel();
    }
    for (final peer in List.of(_clients)) {
      if (peer.side != null) peer.transport.send(event);
    }
  }

  LanMessage sync(LanMessage request) =>
      chessAuthority?.sync(request) ??
      draughtsAuthority?.sync(request) ??
      authority.sync(request);

  LanMessage submit(Side side, LanMessage request) =>
      chessAuthority?.submit(side, request) ??
      draughtsAuthority?.submit(side, request) ??
      authority.submit(side, request);

  bool acceptsHello(Map<String, Object?> body) {
    if (chessAuthority != null) {
      return body['game'] == 'chess' &&
          body['rulesVersion'] == chessRulesVersion;
    }
    if (isDraughts) {
      return body['game'] == 'draughts' &&
          body['variant'] == draughtsAuthority!.variant.name &&
          body['rulesVersion'] == draughtsRulesVersion;
    }
    return (body['game'] == null || body['game'] == 'go') &&
        _sameConfig(LanMessage.parseConfig(body), authority.session.goConfig);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _undoTimer?.cancel();
    for (final peer in List.of(_clients)) {
      await peer.close();
    }
    _clients.clear();
    await _playerCounts.close();
    chessAuthority?.dispose();
  }
}

class _RoomPeer {
  _RoomPeer(
    this.server,
    this.transport,
    this.remoteAddress,
    this.fixedSide,
    this.credential,
  );
  final RoomCoordinator server;
  final MessageTransport transport;
  final Side? fixedSide;
  final String? credential;
  StreamSubscription<void>? _disconnects;
  final String remoteAddress;
  Side? side;
  bool _closed = false;
  StreamSubscription<Object?>? _subscription;
  Timer? _heartbeat;
  DateTime _lastPong = DateTime.now();

  void _sendEncoded(String encoded) =>
      transport.send(LanMessage.decode(encoded));

  void listen() {
    _disconnects = transport.disconnections.listen((_) {
      _heartbeat?.cancel();
      server._remove(this);
    });
    _subscription = transport.messages.listen(
      (raw) => _receive(raw),
      onDone: () {
        _heartbeat?.cancel();
        server._remove(this);
      },
      onError: (_) {
        transport.send(
          LanMessage(LanMessageType.rejected, server.seq, {
            'reason': '无效的联机请求',
          }),
        );
        if (side != null) {
          transport.send(
            server.sync(
              LanMessage(LanMessageType.stateRequest, server.seq, {
                'lastSeq': 0,
              }),
            ),
          );
        }
      },
    );
  }

  void _receive(Object? raw) {
    if (raw is! LanMessage) return;
    try {
      final message = raw;
      if (side == null) {
        if (server._tooManyFailures(remoteAddress)) {
          _sendEncoded(
            LanMessage(LanMessageType.rejected, server.seq, {
              'reason': '口令尝试过多，请稍后重试',
            }).encode(),
          );
          return;
        }
        String? reason;
        if (message.type != LanMessageType.hello) {
          reason = '联机协议版本不一致';
        } else if (message.body['token'] != (credential ?? server.token)) {
          reason = '口令错误';
          server._recordAuthFailure(remoteAddress);
        } else if (!server.acceptsHello(message.body)) {
          reason = '棋盘规则不一致';
        }
        if (reason != null) {
          _sendEncoded(
            LanMessage(LanMessageType.rejected, server.seq, {
              'reason': reason,
            }).encode(),
          );
          return;
        }
        if (server._clients.where((peer) => peer.side != null).length >= 2) {
          _sendEncoded(
            LanMessage(LanMessageType.rejected, server.seq, {
              'reason': '房间已满',
            }).encode(),
          );
          return;
        }
        final requested = message.body['resumeSide'];
        final firstSide = server.chessAuthority != null
            ? Side.white
            : server.draughtsAuthority?.session.rules.firstMove ?? Side.black;
        if (fixedSide != null &&
            requested != null &&
            LanMessage.parseSide(requested) != fixedSide) {
          throw const FormatException('不能恢复其他玩家的座位');
        }
        side =
            fixedSide ??
            (requested == null
                ? (server._clients.any((peer) => peer.side == firstSide)
                      ? firstSide.opponent
                      : firstSide)
                : LanMessage.parseSide(requested));
        if (server._clients.any((peer) => peer != this && peer.side == side)) {
          _sendEncoded(
            LanMessage(LanMessageType.rejected, server.seq, {
              'reason': '原座位仍被占用',
            }).encode(),
          );
          side = null;
          return;
        }
        server._playerCounts.add(server.playerCount);
        _lastPong = DateTime.now();
        _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
          if (DateTime.now().difference(_lastPong) >
              const Duration(seconds: 15)) {
            transport.close();
          } else {
            _sendEncoded(
              LanMessage(LanMessageType.ping, server.seq, {
                'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
              }).encode(),
            );
          }
        });
        _sendEncoded(
          LanMessage(LanMessageType.helloAck, server.seq, {
            'assignedSide': LanMessage.sideCode(side!),
            'started': server.started,
          }).encode(),
        );
        _sendEncoded(
          server
              .sync(
                LanMessage(LanMessageType.stateRequest, server.seq, {
                  'lastSeq': 0,
                }),
              )
              .encode(),
        );
        return;
      }
      if (message.type == LanMessageType.stateRequest) {
        _sendEncoded(server.sync(message).encode());
        return;
      }
      if (message.type == LanMessageType.pong) {
        _lastPong = DateTime.now();
        return;
      }
      if (message.type == LanMessageType.ping) {
        _sendEncoded(
          LanMessage(LanMessageType.pong, server.seq, {
            'nonce': message.body['nonce'],
          }).encode(),
        );
        return;
      }
      if (!server.started) {
        _sendEncoded(
          LanMessage(LanMessageType.rejected, server.seq, {
            'reason': '等待房主开始对局',
          }).encode(),
        );
        return;
      }
      final result = server.submit(side!, message);
      if (result.type == LanMessageType.rejected) {
        _sendEncoded(result.encode());
      } else {
        server._broadcast(result);
      }
    } on FormatException catch (error) {
      _sendEncoded(
        LanMessage(LanMessageType.rejected, server.seq, {
          'reason': error.message,
        }).encode(),
      );
    } catch (_) {
      _sendEncoded(
        LanMessage(LanMessageType.rejected, server.seq, {
          'reason': '无效的联机请求',
        }).encode(),
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    await _subscription?.cancel();
    await _disconnects?.cancel();
    await transport.close();
    server._remove(this);
  }
}

bool _sameConfig(GoConfig left, GoConfig right) =>
    left.boardSize == right.boardSize &&
    left.rules == right.rules &&
    left.komi == right.komi &&
    left.handicap == right.handicap;
