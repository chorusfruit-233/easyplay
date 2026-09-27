import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../game_session.dart';
import 'lan_game.dart';
import 'lan_ports.dart';
import 'lan_protocol.dart';

class LanHostServer {
  LanHostServer({required this.authority, required this.token});
  final LanAuthority authority;
  final String token;
  HttpServer? _server;
  bool _started = false;
  final _clients = <_LanPeer>[];
  final _authFailures = <String, List<DateTime>>{};
  final _playerCounts = StreamController<int>.broadcast();
  Timer? _undoTimer;
  InternetAddress? get address => _server?.address;
  int? get port => _server?.port;
  int get playerCount => _clients.where((peer) => peer.side != null).length;
  bool get started => _started;
  Stream<int> get playerCounts => _playerCounts.stream;

  void startMatch() {
    if (_started) return;
    if (playerCount != 2) throw StateError('对手尚未加入');
    _started = true;
    _broadcast(LanMessage(LanMessageType.matchStart, authority.seq));
  }

  Future<void> start({
    String host = '0.0.0.0',
    int port = lanDefaultPort,
  }) async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(host, port, shared: false);
    } on SocketException catch (error) {
      if (port == 0 || !_portInUse(error)) rethrow;
      for (
        var fallback = port + 1;
        fallback <= 65535 && fallback <= port + lanFallbackPortCount;
        fallback++
      ) {
        try {
          _server = await HttpServer.bind(host, fallback, shared: false);
          break;
        } on SocketException catch (retryError) {
          if (!_portInUse(retryError)) rethrow;
        }
      }
      if (_server == null) {
        throw StateError('建房端口及其后续 10 个端口均被占用，无法创建可扫描的房间');
      }
    }
    _server!.listen(_handle);
  }

  bool _portInUse(SocketException error) =>
      error.osError?.errorCode == 98 ||
      error.toString().contains('shared flag to bind()');

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path == '/easyplay/probe' && request.method == 'GET') {
      final body = jsonEncode({
        'app': 'easyplay',
        'version': lanProtocolVersion,
        'board': authority.session.goConfig.boardSize,
        'players': playerCount,
        'phase': authority.session.gameOver
            ? 'finished'
            : _started
            ? 'playing'
            : 'waiting',
      });
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.contentLength = utf8.encode(body).length
        ..write(body);
      await request.response.close();
      return;
    }
    if (request.uri.path == '/easyplay/ws') {
      try {
        final remoteAddress =
            request.connectionInfo?.remoteAddress.address ?? 'unknown';
        final socket = await WebSocketTransformer.upgrade(request);
        final peer = _LanPeer(this, socket, remoteAddress);
        _clients.add(peer);
        peer.listen();
      } catch (_) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('WebSocket upgrade failed');
        await request.response.close();
      }
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }
    final path = request.uri.path == '/'
        ? 'index.html'
        : request.uri.path.substring(1);
    if (path
        .split('/')
        .any(
          (segment) => segment.isEmpty || segment == '..' || segment == '.',
        )) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    try {
      final data = await rootBundle.load('assets/web/$path');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      request.response.headers
        ..set('Cross-Origin-Opener-Policy', 'same-origin')
        ..set('Cross-Origin-Embedder-Policy', 'require-corp')
        ..set('Cache-Control', 'no-cache');
      request.response.headers.contentType = _contentType(path);
      request.response.contentLength = bytes.length;
      if (request.method == 'GET') request.response.add(bytes);
    } on FlutterError {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Web client is not bundled in this build');
    }
    await request.response.close();
  }

  void _remove(_LanPeer peer) {
    if (_clients.remove(peer) && peer.side != null && !_playerCounts.isClosed) {
      _playerCounts.add(playerCount);
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
        final expired = authority.expireUndo(event.seq);
        if (expired != null) _broadcast(expired);
      });
    } else if (event.type == LanMessageType.undoAccept ||
        event.type == LanMessageType.undoReject) {
      _undoTimer?.cancel();
    }
    final encoded = event.encode();
    for (final peer in List.of(_clients)) {
      if (peer.side != null) peer.socket.add(encoded);
    }
  }

  Future<void> close() async {
    _undoTimer?.cancel();
    for (final peer in List.of(_clients)) {
      await peer.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    await _playerCounts.close();
  }
}

ContentType _contentType(String path) => switch (path.split('.').last) {
  'html' => ContentType.html,
  'js' => ContentType('application', 'javascript'),
  'json' => ContentType.json,
  'wasm' => ContentType('application', 'wasm'),
  'png' => ContentType('image', 'png'),
  'svg' => ContentType('image', 'svg+xml'),
  'woff' || 'woff2' => ContentType('font', 'woff2'),
  'ttf' => ContentType('font', 'ttf'),
  'otf' => ContentType('font', 'otf'),
  _ => ContentType.binary,
};

class _LanPeer {
  _LanPeer(this.server, this.socket, this.remoteAddress);
  final LanHostServer server;
  final WebSocket socket;
  final String remoteAddress;
  Side? side;
  StreamSubscription<Object?>? _subscription;
  Timer? _heartbeat;
  DateTime _lastPong = DateTime.now();

  void listen() {
    _subscription = socket.listen(
      (raw) => _receive(raw),
      onDone: () {
        _heartbeat?.cancel();
        server._remove(this);
      },
      onError: (_) {
        _heartbeat?.cancel();
        server._remove(this);
      },
      cancelOnError: true,
    );
  }

  void _receive(Object? raw) {
    if (raw is! String) return;
    try {
      final message = LanMessage.decode(raw);
      if (side == null) {
        if (server._tooManyFailures(remoteAddress)) {
          socket.add(
            LanMessage(LanMessageType.rejected, server.authority.seq, {
              'reason': '口令尝试过多，请稍后重试',
            }).encode(),
          );
          return;
        }
        String? reason;
        if (message.type != LanMessageType.hello) {
          reason = '联机协议版本不一致';
        } else if (message.body['token'] != server.token) {
          reason = '口令错误';
          server._recordAuthFailure(remoteAddress);
        } else if (!_sameConfig(
          LanMessage.parseConfig(message.body),
          server.authority.session.goConfig,
        )) {
          reason = '棋盘规则不一致';
        }
        if (reason != null) {
          socket.add(
            LanMessage(LanMessageType.rejected, server.authority.seq, {
              'reason': reason,
            }).encode(),
          );
          return;
        }
        if (server._clients.where((peer) => peer.side != null).length >= 2) {
          socket.add(
            LanMessage(LanMessageType.rejected, server.authority.seq, {
              'reason': '房间已满',
            }).encode(),
          );
          return;
        }
        final requested = message.body['resumeSide'];
        side = requested == null
            ? (server._clients.any((peer) => peer.side == Side.black)
                  ? Side.white
                  : Side.black)
            : LanMessage.parseSide(requested);
        if (server._clients.any((peer) => peer != this && peer.side == side)) {
          socket.add(
            LanMessage(LanMessageType.rejected, server.authority.seq, {
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
            socket.close();
          } else {
            socket.add(
              LanMessage(LanMessageType.ping, server.authority.seq, {
                'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
              }).encode(),
            );
          }
        });
        socket.add(
          LanMessage(LanMessageType.helloAck, server.authority.seq, {
            'assignedSide': LanMessage.sideCode(side!),
            'started': server.started,
          }).encode(),
        );
        socket.add(
          server.authority
              .sync(
                LanMessage(LanMessageType.stateRequest, server.authority.seq, {
                  'lastSeq': 0,
                }),
              )
              .encode(),
        );
        return;
      }
      if (message.type == LanMessageType.stateRequest) {
        socket.add(server.authority.sync(message).encode());
        return;
      }
      if (message.type == LanMessageType.pong) {
        _lastPong = DateTime.now();
        return;
      }
      if (message.type == LanMessageType.ping) {
        socket.add(
          LanMessage(LanMessageType.pong, server.authority.seq, {
            'nonce': message.body['nonce'],
          }).encode(),
        );
        return;
      }
      if (!server.started) {
        socket.add(
          LanMessage(LanMessageType.rejected, server.authority.seq, {
            'reason': '等待房主开始对局',
          }).encode(),
        );
        return;
      }
      final result = server.authority.submit(side!, message);
      if (result.type == LanMessageType.rejected) {
        socket.add(result.encode());
      } else {
        server._broadcast(result);
      }
    } on FormatException catch (error) {
      socket.add(
        LanMessage(LanMessageType.rejected, server.authority.seq, {
          'reason': error.message,
        }).encode(),
      );
    } catch (_) {
      socket.add(
        LanMessage(LanMessageType.rejected, server.authority.seq, {
          'reason': '无效的联机请求',
        }).encode(),
      );
    }
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    await _subscription?.cancel();
    await socket.close();
    server._remove(this);
  }
}

bool _sameConfig(GoConfig left, GoConfig right) =>
    left.boardSize == right.boardSize &&
    left.rules == right.rules &&
    left.komi == right.komi &&
    left.handicap == right.handicap;

class LanClientConnection {
  LanClientConnection(this.config);
  final GoConfig config;
  final _messages = StreamController<LanMessage>.broadcast();
  final _disconnections = StreamController<void>.broadcast();
  WebSocket? _socket;
  Uri? _uri;
  String? _token;
  Timer? _heartbeat;
  DateTime _lastPong = DateTime.now();
  LanReplica? replica;
  Side? side;
  bool started = false;
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
    final socket = await WebSocket.connect(socketUri.toString());
    _socket = socket;
    replica ??= LanReplica(config);
    final handshake = Completer<void>();
    socket.listen(
      (raw) {
        try {
          final message = LanMessage.decode(raw as String);
          _lastPong = DateTime.now();
          if (message.type == LanMessageType.ping) {
            socket.add(
              LanMessage(LanMessageType.pong, replica?.seq ?? 0, {
                'nonce': message.body['nonce'],
              }).encode(),
            );
            return;
          }
          if (message.type == LanMessageType.helloAck) {
            side = LanMessage.parseSide(message.body['assignedSide']);
            started = message.body['started'] as bool;
            if (!handshake.isCompleted) handshake.complete();
          } else if (message.type == LanMessageType.matchStart) {
            started = true;
          } else if (message.type == LanMessageType.rejected &&
              !handshake.isCompleted) {
            handshake.completeError(
              StateError(message.body['reason'] as String),
            );
          } else if (message.type == LanMessageType.stateSync ||
              message.type == LanMessageType.move ||
              message.type == LanMessageType.pass ||
              message.type == LanMessageType.resign ||
              LanMessage.eventTypes.contains(message.type)) {
            replica?.receive(message);
          }
          _messages.add(message);
        } catch (error) {
          if (!handshake.isCompleted) handshake.completeError(error);
        }
      },
      onDone: () {
        if (identical(_socket, socket)) {
          _heartbeat?.cancel();
          _socket = null;
          if (!_disconnections.isClosed) _disconnections.add(null);
        }
        if (!handshake.isCompleted) {
          handshake.completeError(StateError('连接已关闭'));
        }
      },
      onError: (Object error) {
        if (identical(_socket, socket)) {
          _heartbeat?.cancel();
          _socket = null;
          if (!_disconnections.isClosed) _disconnections.add(null);
        }
        if (!handshake.isCompleted) handshake.completeError(error);
      },
    );
    socket.add(
      LanMessage(LanMessageType.hello, 0, {
        'roomVersion': lanProtocolVersion,
        ...LanMessage.configToWire(config),
        'token': token,
        if (side != null) 'resumeSide': LanMessage.sideCode(side!),
      }).encode(),
    );
    try {
      await handshake.future.timeout(const Duration(seconds: 5));
      _lastPong = DateTime.now();
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
        if (DateTime.now().difference(_lastPong) >
            const Duration(seconds: 15)) {
          socket.close();
        } else {
          socket.add(
            LanMessage(LanMessageType.ping, replica?.seq ?? 0, {
              'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
            }).encode(),
          );
        }
      });
    } catch (_) {
      await socket.close();
      if (identical(_socket, socket)) _socket = null;
      rethrow;
    }
  }

  void send(LanMessage message) {
    if (_socket == null) throw StateError('尚未连接房间');
    _socket!.add(message.encode());
  }

  Future<void> disconnect() async {
    await _socket?.close();
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    await _socket?.close();
    await _messages.close();
    await _disconnections.close();
    _socket = null;
  }
}
