import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../../lan/lan_protocol.dart' show lanProtocolVersion;
import '../../lan/lan_transport_io.dart' show SocketMessageTransport;
import '../../lan/message_transport.dart';
import 'card_room_coordinator.dart';

bool get cardLanHostingSupported => true;
Future<MessageTransport> connectCardSocket(Uri uri) async =>
    SocketMessageTransport(
      await WebSocket.connect(
        uri.replace(path: '/easyplay/ws').toString(),
      ).timeout(const Duration(seconds: 8)),
    );

class CardLanServer {
  CardLanServer(this.coordinator);
  final CardRoomCoordinator coordinator;
  HttpServer? _server;
  int? get port => _server?.port;
  Future<void> start({String host = '0.0.0.0', int port = 8080}) async {
    if (_server != null) return;
    for (
      var candidate = port;
      candidate <= (port == 0 ? 0 : port + 10);
      candidate++
    ) {
      try {
        _server = await HttpServer.bind(host, candidate);
        break;
      } on SocketException {
        if (candidate == (port == 0 ? 0 : port + 10)) rethrow;
      }
    }
    _server!.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path == '/easyplay/probe') {
        request.response.headers.contentType = ContentType.json;
        final body = jsonEncode({
          'app': 'easyplay',
          'version': lanProtocolVersion,
          'game': 'doudizhu',
          'rulesVersion': 1,
          'protocolVersion': 1,
          'players': coordinator.playerCount,
          'maxPlayers': 3,
          'phase': coordinator.session.phase.name,
        });
        request.response.contentLength = utf8.encode(body).length;
        request.response.write(body);
      } else if (request.uri.path == '/easyplay/ws') {
        coordinator.attach(
          SocketMessageTransport(await WebSocketTransformer.upgrade(request)),
        );
        return;
      } else {
        if (!['GET', 'HEAD'].contains(request.method)) {
          request.response.statusCode = 405;
        } else {
          final path = request.uri.path == '/'
              ? 'index.html'
              : request.uri.path.substring(1);
          if (path.split('/').any((s) => s.isEmpty || s == '..' || s == '.')) {
            request.response.statusCode = 400;
          } else {
            try {
              final data = await rootBundle.load('assets/web/$path');
              request.response.headers
                ..set('Cross-Origin-Opener-Policy', 'same-origin')
                ..set('Cross-Origin-Embedder-Policy', 'require-corp')
                ..set('Cache-Control', 'no-cache');
              request.response.headers.contentType = switch (path
                  .split('.')
                  .last) {
                'html' => ContentType.html,
                'js' => ContentType('application', 'javascript'),
                'json' => ContentType.json,
                'wasm' => ContentType('application', 'wasm'),
                'png' => ContentType('image', 'png'),
                'svg' => ContentType('image', 'svg+xml'),
                'woff2' => ContentType('font', 'woff2'),
                'ttf' => ContentType('font', 'ttf'),
                _ => ContentType.binary,
              };
              final bytes = data.buffer.asUint8List(
                data.offsetInBytes,
                data.lengthInBytes,
              );
              request.response.contentLength = bytes.length;
              if (request.method == 'GET') request.response.add(bytes);
            } catch (_) {
              request.response.statusCode = 404;
            }
          }
        }
      }
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = 400;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}
