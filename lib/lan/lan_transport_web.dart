import '../chess/chess_session.dart' show chessRulesVersion;
import 'chess_lan_game.dart';
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../game_session.dart';
import '../draughts/draughts_variant.dart';
import '../draughts/draughts_session.dart' show draughtsRulesVersion;
import 'draughts_lan_game.dart';
import 'lan_game.dart';
import 'lan_protocol.dart';

class LanHostServer {
  // Preserve the existing named Go constructor parameter for callers.
  LanHostServer({
    LanAuthority? authority,
    this.draughtsAuthority,
    this.chessAuthority,
    required this.token,
  })
    // ignore: prefer_initializing_formals
    : _authority = authority;
  final LanAuthority? _authority;
  LanAuthority get authority => _authority!;
  final DraughtsAuthority? draughtsAuthority;
  final ChessAuthority? chessAuthority;
  final String token;
  int? get port => null;
  int get playerCount => 0;
  bool get started => false;
  Stream<int> get playerCounts => const Stream.empty();
  void startMatch() => throw UnsupportedError('Web 端不能开始房间');
  Future<void> start({String host = '0.0.0.0', int port = 8080}) async =>
      throw UnsupportedError('Web 端不能创建局域网监听服务');
  Future<void> close() async {}
}

class LanClientConnection {
  LanClientConnection(this.config) : draughtsVariant = null, isChess = false;
  LanClientConnection.draughts(DraughtsVariant variant)
    : config = const GoConfig(),
      draughtsVariant = variant,
      isChess = false;
  LanClientConnection.chess()
    : config = const GoConfig(),
      draughtsVariant = null,
      isChess = true;
  final bool isChess;
  final GoConfig config;
  final DraughtsVariant? draughtsVariant;
  final _messages = StreamController<LanMessage>.broadcast();
  final _disconnections = StreamController<void>.broadcast();
  web.WebSocket? _socket;
  Uri? _uri;
  String? _token;
  Timer? _heartbeat;
  DateTime _lastPong = DateTime.now();
  LanReplica? replica;
  DraughtsLanReplica? draughtsReplica;
  ChessLanReplica? chessReplica;
  Side? side;
  bool started = false;
  int get seq => chessReplica?.seq ?? draughtsReplica?.seq ?? replica?.seq ?? 0;
  Stream<LanMessage> get messages => _messages.stream;
  Stream<void> get disconnections => _disconnections.stream;

  Future<void> reconnect() async {
    if (_uri == null || _token == null) throw StateError('没有可重连的房间');
    await connect(_uri!, token: _token!);
  }

  Future<void> connect(Uri uri, {required String token}) async {
    _uri = uri;
    _token = token;
    final socketUri = uri.path.endsWith('/easyplay/ws')
        ? uri
        : uri.replace(path: '/easyplay/ws');
    final socket = web.WebSocket(socketUri.toString());
    _socket = socket;
    if (isChess) {
      chessReplica ??= ChessLanReplica();
    } else if (draughtsVariant != null) {
      draughtsReplica ??= DraughtsLanReplica(draughtsVariant!);
    } else {
      replica ??= LanReplica(config);
    }
    final opened = Completer<void>();
    final handshake = Completer<void>();
    socket.onopen = ((web.Event _) {
      if (!opened.isCompleted) opened.complete();
    }).toJS;
    socket.onerror = ((web.Event _) {
      if (!opened.isCompleted) opened.completeError(StateError('连接失败'));
      if (!handshake.isCompleted) handshake.completeError(StateError('连接失败'));
    }).toJS;
    socket.onclose = ((web.Event _) {
      if (identical(_socket, socket)) {
        _heartbeat?.cancel();
        _socket = null;
        if (!_disconnections.isClosed) _disconnections.add(null);
      }
      if (!handshake.isCompleted) handshake.completeError(StateError('连接已关闭'));
    }).toJS;
    socket.onmessage = ((web.Event event) {
      if (!identical(_socket, socket)) return;
      try {
        final raw = (event as web.MessageEvent).data;
        if (raw == null || !raw.isA<JSString>()) return;
        final message = LanMessage.decode((raw as JSString).toDart);
        _lastPong = DateTime.now();
        if (message.type == LanMessageType.ping) {
          socket.send(
            LanMessage(LanMessageType.pong, seq, {
              'nonce': message.body['nonce'],
            }).encode().toJS,
          );
          return;
        }
        if (message.type == LanMessageType.helloAck) {
          side = LanMessage.parseSide(message.body['assignedSide']);
          started = message.body['started'] as bool;
        } else if (message.type == LanMessageType.matchStart) {
          started = true;
        } else if (message.type == LanMessageType.rejected &&
            !handshake.isCompleted) {
          handshake.completeError(StateError(message.body['reason'] as String));
        } else if (message.type == LanMessageType.stateSync ||
            LanMessage.eventTypes.contains(message.type)) {
          final accepted = isChess
              ? chessReplica!.receive(message)
              : draughtsVariant != null
              ? draughtsReplica!.receive(message)
              : replica!.receive(message);
          if (!accepted) {
            if (message.type == LanMessageType.stateSync) {
              throw const FormatException('对局同步失败');
            }
            final stateRequest =
                chessReplica?.stateRequest() ??
                draughtsReplica?.stateRequest() ??
                replica!.stateRequest();
            socket.send(stateRequest.encode().toJS);
            return;
          }
          if (message.type == LanMessageType.stateSync &&
              !handshake.isCompleted) {
            handshake.complete();
          }
        }
        _messages.add(message);
      } catch (error) {
        if (!handshake.isCompleted) handshake.completeError(error);
      }
    }).toJS;
    try {
      await opened.future.timeout(const Duration(seconds: 5));
      socket.send(
        LanMessage(LanMessageType.hello, 0, {
          'roomVersion': lanProtocolVersion,
          if (!isChess && draughtsVariant == null)
            ...LanMessage.configToWire(config),
          'game': isChess
              ? 'chess'
              : draughtsVariant == null
              ? 'go'
              : 'draughts',
          if (draughtsVariant != null) 'variant': draughtsVariant!.name,
          if (draughtsVariant != null) 'rulesVersion': draughtsRulesVersion,
          if (isChess) 'rulesVersion': chessRulesVersion,
          'token': token,
          if (side != null) 'resumeSide': LanMessage.sideCode(side!),
        }).encode().toJS,
      );
      await handshake.future.timeout(const Duration(seconds: 5));
      _lastPong = DateTime.now();
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
        if (DateTime.now().difference(_lastPong) >
            const Duration(seconds: 15)) {
          socket.close();
        } else if (socket.readyState == web.WebSocket.OPEN) {
          socket.send(
            LanMessage(LanMessageType.ping, seq, {
              'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
            }).encode().toJS,
          );
        }
      });
    } catch (_) {
      socket.close();
      if (identical(_socket, socket)) _socket = null;
      rethrow;
    }
  }

  void send(LanMessage message) {
    final socket = _socket;
    if (socket == null || socket.readyState != web.WebSocket.OPEN) {
      throw StateError('尚未连接房间');
    }
    socket.send(message.encode().toJS);
  }

  Future<void> disconnect() async {
    _socket?.close();
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    _socket?.close();
    _socket = null;
    chessReplica?.dispose();
    if (!_messages.isClosed) await _messages.close();
    if (!_disconnections.isClosed) await _disconnections.close();
  }
}
