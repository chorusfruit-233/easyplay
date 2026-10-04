import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'lan_protocol.dart';
import 'message_transport.dart';
import 'rtc_framing.dart';

abstract interface class RtcTextChannel {
  Stream<String> get incoming;
  Stream<void> get disconnections;
  int get maxMessageSize;
  Future<void> sendText(String text);
  Future<void> close();
}

/// One fragment per scheduling turn lets small control messages pass a sync.
class RtcMessageTransport implements MessageTransport {
  RtcMessageTransport(this.channel) {
    _incoming = channel.incoming.listen((raw) {
      try {
        final message = _assembler.receive(raw);
        if (message != null) _receive(message);
      } catch (_) {
        _receiveError(const FormatException('传输校验失败，请重新同步'));
      }
    }, onError: _receiveError);
    _disconnects = channel.disconnections.listen((_) {
      if (!_closed) _disconnections.add(null);
    });
    _expiry = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_assembler.expire()) {
        _receiveError(const FormatException('同步分片超时'));
      }
    });
  }
  final RtcTextChannel channel;
  final _assembler = RtcReassembler();
  late final _messages = StreamController<LanMessage>.broadcast(
    onListen: _attachReceiver,
  );
  // DataChannel may open and deliver hello before RtcRoom attaches. Keep only
  // this initial handoff buffered, with the same limits as the send queue.
  final _pending = Queue<LanMessage>();
  int _pendingBytes = 0;
  Object? _pendingError;
  bool _receiverAttached = false;
  final _disconnections = StreamController<void>.broadcast();
  final _small = Queue<_Outgoing>(), _large = Queue<_Outgoing>();
  late final StreamSubscription<String> _incoming;
  late final StreamSubscription<void> _disconnects;
  late final Timer _expiry;
  int _queuedBytes = 0;
  bool _pumping = false, _closed = false;
  @override
  Stream<LanMessage> get messages => _messages.stream;
  @override
  Stream<void> get disconnections => _disconnections.stream;
  void _attachReceiver() {
    _receiverAttached = true;
    if (_pendingError != null) {
      _messages.addError(_pendingError!);
      _pendingError = null;
    }
    while (_pending.isNotEmpty) {
      _messages.add(_pending.removeFirst());
    }
    _pendingBytes = 0;
  }

  void _receive(LanMessage message) {
    if (_closed) return;
    if (_receiverAttached) {
      _messages.add(message);
      return;
    }
    if (_pendingError != null) return;
    final size = utf8.encode(message.encode()).length;
    if (_pending.length >= 64 || _pendingBytes + size > 8 * 1024 * 1024) {
      _receiveError(const FormatException('接收队列超限'));
      return;
    }
    _pending.add(message);
    _pendingBytes += size;
  }

  void _receiveError(Object error) {
    if (_closed) return;
    if (_receiverAttached) {
      _messages.addError(error);
    } else {
      _pending.clear();
      _pendingBytes = 0;
      _pendingError = error;
    }
  }

  @override
  void send(LanMessage message) {
    if (_closed) throw StateError('通道已关闭');
    final size = utf8.encode(message.encode()).length;
    if (size > rtcMaxMessageBytes ||
        _queuedBytes + size > 8 * 1024 * 1024 ||
        _small.length + _large.length >= 64) {
      throw const FormatException('发送队列超限');
    }
    final frames = rtcFrames(
      message,
      maxFrameBytes: channel.maxMessageSize,
    ).iterator;
    if (!frames.moveNext()) return;
    final outgoing = _Outgoing(frames, size);
    (size < 8192 ? _small : _large).add(outgoing);
    _queuedBytes += size;
    if (!_pumping) unawaited(_pump());
  }

  Future<void> _pump() async {
    _pumping = true;
    try {
      while (!_closed && (_small.isNotEmpty || _large.isNotEmpty)) {
        final queue = _small.isNotEmpty ? _small : _large;
        final next = queue.first;
        await channel.sendText(next.frames.current);
        if (_closed) break;
        if (!next.frames.moveNext()) {
          queue.removeFirst();
          _queuedBytes -= next.size;
        }
        // Microtask scheduling is not throttled like background-tab timers.
        // The channel's bufferedAmount wait yields to network/control events.
        await Future<void>.value();
      }
    } catch (_) {
      if (!_closed) {
        _disconnections.add(null);
        unawaited(close());
      }
    } finally {
      _pumping = false;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _expiry.cancel();
    _assembler.clear();
    _pending.clear();
    _pendingBytes = 0;
    _pendingError = null;
    _small.clear();
    _large.clear();
    _queuedBytes = 0;
    await _incoming.cancel();
    await _disconnects.cancel();
    await channel.close();
    await _messages.close();
    await _disconnections.close();
  }
}

class _Outgoing {
  _Outgoing(this.frames, this.size);
  final Iterator<String> frames;
  final int size;
}
