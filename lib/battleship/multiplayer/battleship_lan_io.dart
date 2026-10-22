import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../lan/lan_ports.dart';
import '../../lan/lan_protocol.dart' show lanProtocolVersion;
import '../../lan/lan_transport_io.dart' show SocketMessageTransport;
import '../../lan/message_transport.dart';
import '../battleship_model.dart' show battleshipRulesVersion;
import 'battleship_room_coordinator.dart';

bool get battleshipLanHostingSupported => true;

Future<MessageTransport> connectBattleshipSocket(Uri uri) async {
  if (!['ws', 'wss'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('联机地址无效');
  }
  return SocketMessageTransport(
    await WebSocket.connect(
      uri.replace(path: '/easyplay/ws', query: '', fragment: '').toString(),
    ).timeout(const Duration(seconds: 8)),
  );
}

/// Native room endpoint, including the bundled browser client for quick join.
class BattleshipLanServer {
  BattleshipLanServer(this.coordinator);
  final BattleshipRoomCoordinator coordinator;
  HttpServer? _server;
  int? get port => _server?.port;

  Future<void> start({
    String host = '0.0.0.0',
    int port = lanDefaultPort,
  }) async {
    if (_server != null) return;
    if (port < 0 || port > 65535) throw ArgumentError.value(port, 'port');
    final last = port == 0 ? 0 : (port + lanFallbackPortCount).clamp(1, 65535);
    for (var candidate = port; candidate <= last; candidate++) {
      try {
        _server = await HttpServer.bind(host, candidate);
        break;
      } on SocketException catch (error) {
        final busy =
            error.osError?.errorCode == 98 ||
            error.osError?.errorCode == 48 ||
            error.osError?.errorCode == 10048;
        if (!busy || candidate == last) rethrow;
      }
    }
    _server!.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path == '/easyplay/probe' && request.method == 'GET') {
        final body = jsonEncode({
          'app': 'easyplay',
          'version': lanProtocolVersion,
          'game': 'battleship',
          'rulesVersion': battleshipRulesVersion,
          'protocolVersion': 1,
          'players': coordinator.playerCount,
          'maxPlayers': 2,
          'phase': coordinator.session.phase.name,
        });
        request.response
          ..headers.contentType = ContentType.json
          ..contentLength = utf8.encode(body).length
          ..write(body);
      } else if (request.uri.path == '/easyplay/ws') {
        coordinator.attach(
          SocketMessageTransport(await WebSocketTransformer.upgrade(request)),
        );
        return;
      } else if (!['GET', 'HEAD'].contains(request.method)) {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        final path = request.uri.path == '/'
            ? 'index.html'
            : request.uri.path.substring(1);
        if (path.contains('\\') ||
            path.contains('\u0000') ||
            path.split('/').any((s) => s.isEmpty || s == '..' || s == '.')) {
          request.response.statusCode = HttpStatus.badRequest;
        } else {
          try {
            final data = await rootBundle.load('assets/web/$path');
            final bytes = data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
            request.response.headers
              ..set('Cross-Origin-Opener-Policy', 'same-origin')
              ..set('Cross-Origin-Embedder-Policy', 'require-corp')
              ..set('Cache-Control', 'no-cache')
              ..contentType = _contentType(path);
            request.response.contentLength = bytes.length;
            if (request.method == 'GET') request.response.add(bytes);
          } catch (_) {
            request.response.statusCode = HttpStatus.notFound;
          }
        }
      }
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      } catch (_) {
        // The peer may have gone away during an upgrade or asset response.
      }
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}

ContentType _contentType(String path) => switch (path.split('.').last) {
  'html' => ContentType.html,
  'js' || 'mjs' => ContentType('application', 'javascript'),
  'json' => ContentType.json,
  'wasm' => ContentType('application', 'wasm'),
  'png' => ContentType('image', 'png'),
  'svg' => ContentType('image', 'svg+xml'),
  'woff' || 'woff2' => ContentType('font', 'woff2'),
  'ttf' => ContentType('font', 'ttf'),
  'otf' => ContentType('font', 'otf'),
  _ => ContentType.binary,
};
