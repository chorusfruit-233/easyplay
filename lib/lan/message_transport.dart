import 'dart:async';

import 'lan_protocol.dart';

abstract interface class MessageTransport {
  Stream<LanMessage> get messages;
  Stream<void> get disconnections;
  void send(LanMessage message);
  Future<void> close();
}

/// An asynchronous pair also lets the browser host use a real local replica.
class MemoryTransport implements MessageTransport {
  MemoryTransport._();
  static (MemoryTransport, MemoryTransport) pair() {
    final a = MemoryTransport._();
    final b = MemoryTransport._();
    a._other = b;
    b._other = a;
    return (a, b);
  }

  late final MemoryTransport _other;
  final _messages = StreamController<LanMessage>.broadcast();
  final _disconnections = StreamController<void>.broadcast();
  bool _closed = false;
  @override
  Stream<LanMessage> get messages => _messages.stream;
  @override
  Stream<void> get disconnections => _disconnections.stream;
  @override
  void send(LanMessage message) {
    if (_closed || _other._closed) throw StateError('连接已关闭');
    _other._messages.add(message);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_other._closed) _other._disconnections.add(null);
    await _messages.close();
    await _disconnections.close();
  }
}
