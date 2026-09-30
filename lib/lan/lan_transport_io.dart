import '../chess/chess_session.dart' show chessRulesVersion;
import 'chess_lan_game.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../game_session.dart';
import '../draughts/draughts_variant.dart';
import '../draughts/draughts_session.dart' show draughtsRulesVersion;
import 'draughts_lan_game.dart';
import 'lan_game.dart';
import 'lan_ports.dart';
import 'lan_protocol.dart';
import 'lan_rematch.dart';

class LanHostServer {
  // Preserve the existing named Go constructor parameter for callers.
  LanHostServer({
    LanAuthority? authority,
    this.draughtsAuthority,
    this.chessAuthority,
    required this.token,
  })
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
  final DraughtsAuthority? draughtsAuthority;
  final ChessAuthority? chessAuthority;
  LanAuthority get authority => _authority!;
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
  bool get isDraughts => draughtsAuthority != null;
  int get seq => chessAuthority?.seq ?? draughtsAuthority?.seq ?? authority.seq;
  int get boardSize => chessAuthority != null
      ? 8
      : draughtsAuthority?.session.rules.boardSize ??
            authority.session.goConfig.boardSize;
  bool get gameOver =>
      chessAuthority?.session.gameOver ??
      draughtsAuthority?.session.gameOver ??
      authority.session.gameOver;
  LanRematchRequest? get _rematchRequest => chessAuthority != null
      ? chessAuthority!.rematchRequest
      : draughtsAuthority != null
      ? draughtsAuthority!.rematchRequest
      : authority.rematchRequest;
  Stream<int> get playerCounts => _playerCounts.stream;

  void startMatch() {
    if (_started) return;
    if (playerCount != 2) throw StateError('对手尚未加入');
    _started = true;
    _broadcast(LanMessage(LanMessageType.matchStart, seq));
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
        'board': boardSize,
        'game': chessAuthority != null
            ? 'chess'
            : isDraughts
            ? 'draughts'
            : 'go',
        if (draughtsAuthority != null)
          'variant': draughtsAuthority!.variant.name,
        'players': playerCount,
        'phase': gameOver
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
    final encoded = event.encode();
    for (final peer in List.of(_clients)) {
      if (peer.side != null) peer.socket.add(encoded);
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
    _undoTimer?.cancel();
    for (final peer in List.of(_clients)) {
      await peer.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    await _playerCounts.close();
    chessAuthority?.dispose();
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
            LanMessage(LanMessageType.rejected, server.seq, {
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
        } else if (!server.acceptsHello(message.body)) {
          reason = '棋盘规则不一致';
        }
        if (reason != null) {
          socket.add(
            LanMessage(LanMessageType.rejected, server.seq, {
              'reason': reason,
            }).encode(),
          );
          return;
        }
        if (server._clients.where((peer) => peer.side != null).length >= 2) {
          socket.add(
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
        side = requested == null
            ? (server._clients.any((peer) => peer.side == firstSide)
                  ? firstSide.opponent
                  : firstSide)
            : LanMessage.parseSide(requested);
        if (server._clients.any((peer) => peer != this && peer.side == side)) {
          socket.add(
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
            socket.close();
          } else {
            socket.add(
              LanMessage(LanMessageType.ping, server.seq, {
                'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
              }).encode(),
            );
          }
        });
        socket.add(
          LanMessage(LanMessageType.helloAck, server.seq, {
            'assignedSide': LanMessage.sideCode(side!),
            'started': server.started,
          }).encode(),
        );
        socket.add(
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
        socket.add(server.sync(message).encode());
        return;
      }
      if (message.type == LanMessageType.pong) {
        _lastPong = DateTime.now();
        return;
      }
      if (message.type == LanMessageType.ping) {
        socket.add(
          LanMessage(LanMessageType.pong, server.seq, {
            'nonce': message.body['nonce'],
          }).encode(),
        );
        return;
      }
      if (!server.started) {
        socket.add(
          LanMessage(LanMessageType.rejected, server.seq, {
            'reason': '等待房主开始对局',
          }).encode(),
        );
        return;
      }
      final result = server.submit(side!, message);
      if (result.type == LanMessageType.rejected) {
        socket.add(result.encode());
      } else {
        server._broadcast(result);
      }
    } on FormatException catch (error) {
      socket.add(
        LanMessage(LanMessageType.rejected, server.seq, {
          'reason': error.message,
        }).encode(),
      );
    } catch (_) {
      socket.add(
        LanMessage(LanMessageType.rejected, server.seq, {
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
  WebSocket? _socket;
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
    final socket = await WebSocket.connect(socketUri.toString());
    _socket = socket;
    if (isChess) {
      chessReplica ??= ChessLanReplica();
    } else if (draughtsVariant != null) {
      draughtsReplica ??= DraughtsLanReplica(draughtsVariant!);
    } else {
      replica ??= LanReplica(config);
    }
    final handshake = Completer<void>();
    socket.listen(
      (raw) {
        if (!identical(_socket, socket)) return;
        try {
          final message = LanMessage.decode(raw as String);
          _lastPong = DateTime.now();
          if (message.type == LanMessageType.ping) {
            socket.add(
              LanMessage(LanMessageType.pong, seq, {
                'nonce': message.body['nonce'],
              }).encode(),
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
            handshake.completeError(
              StateError(message.body['reason'] as String),
            );
          } else if (message.type == LanMessageType.stateSync ||
              message.type == LanMessageType.move ||
              message.type == LanMessageType.pass ||
              message.type == LanMessageType.resign ||
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
              socket.add(stateRequest.encode());
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
            LanMessage(LanMessageType.ping, seq, {
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
    chessReplica?.dispose();
    if (!_messages.isClosed) await _messages.close();
    if (!_disconnections.isClosed) await _disconnections.close();
    _socket = null;
  }
}
