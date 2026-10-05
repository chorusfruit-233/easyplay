import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../../lan/message_transport.dart';
import '../../lan/lan_protocol.dart';
export 'card_lan_stub.dart' show CardLanServer, cardLanHostingSupported;

Future<MessageTransport> connectCardSocket(Uri uri) async {
  final transport = _CardWebSocket(
    web.WebSocket(uri.replace(path: '/easyplay/ws').toString()),
  );
  try {
    await transport.opened.future.timeout(const Duration(seconds: 8));
    return transport;
  } catch (_) {
    await transport.close();
    rethrow;
  }
}

class _CardWebSocket implements MessageTransport {
  _CardWebSocket(this.socket) {
    unawaited(opened.future.then<void>((_) {}, onError: (Object _) {}));
    socket.onopen = ((web.Event _) {
      if (!opened.isCompleted) opened.complete();
    }).toJS;
    socket.onmessage = ((web.MessageEvent e) {
      try {
        if (e.data.isA<JSString>() && !_closed) {
          _messages.add(LanMessage.decode((e.data as JSString).toDart));
        }
      } catch (_) {
        if (!_closed) _messages.addError(const FormatException('消息无效'));
      }
    }).toJS;
    socket.onclose = ((web.Event _) {
      if (!opened.isCompleted) opened.completeError(StateError('连接中断'));
      if (!_closed) _lost.add(null);
    }).toJS;
    socket.onerror = ((web.Event _) {
      if (!opened.isCompleted) opened.completeError(StateError('连接失败'));
      if (!_closed) _lost.add(null);
    }).toJS;
  }
  final web.WebSocket socket;
  final opened = Completer<void>();
  final _messages = StreamController<LanMessage>.broadcast();
  final _lost = StreamController<void>.broadcast();
  bool _closed = false;
  @override
  Stream<LanMessage> get messages => _messages.stream;
  @override
  Stream<void> get disconnections => _lost.stream;
  @override
  void send(LanMessage m) {
    if (_closed || socket.readyState != web.WebSocket.OPEN) {
      throw StateError('连接已断开');
    }
    socket.send(m.encode().toJS);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    socket.close();
    await _messages.close();
    await _lost.close();
  }
}
