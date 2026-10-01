import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'message_transport.dart';
import 'rtc_channel.dart';
import 'rtc_framing.dart';
import 'rtc_ice_config.dart';

bool get rtcSupported =>
    web.window.has('RTCPeerConnection') && web.window.has('RTCDataChannel');

class RtcPeer {
  RtcPeer({List<Map<String, Object?>>? iceServers}) {
    if (!rtcSupported) throw UnsupportedError('浏览器不支持 WebRTC');
    _pc = web.RTCPeerConnection(
      web.RTCConfiguration(
        iceServers:
            (iceServers ?? rtcStunServers(rtcDomesticStunUrls)).jsify()
                as JSArray<web.RTCIceServer>,
      ),
    );
    _pc.ondatachannel = ((web.RTCDataChannelEvent event) {
      _bind(event.channel);
    }).toJS;
    _pc.onconnectionstatechange = ((web.Event _) {
      _state = '${_pc.connectionState} / ICE ${_pc.iceConnectionState}';
      if (!_states.isClosed) _states.add(_state);
      if (_pc.connectionState == 'failed' || _pc.connectionState == 'closed') {
        _fail('当前网络无法直连；可重试或稍后启用 TURN。房主关闭页面后房间无法恢复。');
      }
    }).toJS;
    // Consume errors until the lobby starts awaiting the channel.
    unawaited(_opened.future.then<void>((_) {}, onError: (Object _) {}));
  }
  late final web.RTCPeerConnection _pc;
  final _opened = Completer<MessageTransport>();
  final _states = StreamController<String>.broadcast();
  String _state = '等待邀请';
  bool _closed = false;
  _WebChannel? _channel;
  RtcMessageTransport? _transport;
  Stream<String> get states => _states.stream;
  String get state => _state;
  Future<MessageTransport> get transport => _opened.future.timeout(
    const Duration(seconds: 45),
    onTimeout: () {
      unawaited(close());
      throw StateError('连接超时：当前网络无法直连，可重试或稍后启用 TURN');
    },
  );

  void _fail(String reason) {
    if (!_opened.isCompleted) _opened.completeError(StateError(reason));
    _channel?.notifyDisconnect();
  }

  void _bind(web.RTCDataChannel data) {
    if (_channel != null ||
        data.label != 'easyplay-game' ||
        !data.ordered ||
        data.maxRetransmits != null ||
        data.maxPacketLifeTime != null) {
      data.close();
      return;
    }
    _channel = _WebChannel(
      data,
      () => _pc.sctp?.maxMessageSize.toInt() ?? rtcMaxFrameBytes,
    );
    _transport = RtcMessageTransport(_channel!);
    data.onopen = ((web.Event _) {
      _state = '通道已打开，正在握手/同步';
      _states.add(_state);
      if (!_opened.isCompleted) _opened.complete(_transport!);
    }).toJS;
  }

  Future<String> _gather(web.RTCSessionDescriptionInit description) async {
    await _pc
        .setLocalDescription(
          web.RTCLocalSessionDescriptionInit(
            type: description.type,
            sdp: description.sdp,
          ),
        )
        .toDart;
    final complete = Completer<void>();
    _pc.onicegatheringstatechange = ((web.Event _) {
      if (_pc.iceGatheringState == 'complete' && !complete.isCompleted) {
        complete.complete();
      }
    }).toJS;
    if (_pc.iceGatheringState == 'complete') complete.complete();
    try {
      await complete.future.timeout(const Duration(seconds: 15));
      if (_closed) throw StateError('协商已取消');
      final sdp = _pc.localDescription?.sdp;
      if (sdp == null || !sdp.contains('a=candidate:')) {
        throw StateError('未搜集到连接候选，请检查 STUN 或网络');
      }
      return sdp;
    } on TimeoutException {
      if (_closed) throw StateError('协商已取消');
      final sdp = _pc.localDescription?.sdp;
      // A dead provider must not discard candidates from responsive providers.
      // Manual signaling exports this snapshot; later candidates are not sent.
      if (sdp != null && sdp.contains(' typ srflx')) {
        _state = '部分 STUN 服务超时，已使用可用的跨网候选';
        _states.add(_state);
        return sdp;
      }
      await close();
      throw StateError('STUN 服务未响应，请在连接选项切换服务或检查网络；同网可关闭 STUN 后重试');
    } catch (_) {
      await close();
      rethrow;
    } finally {
      _pc.onicegatheringstatechange = null;
    }
  }

  Future<String> createOffer() async {
    _bind(
      _pc.createDataChannel(
        'easyplay-game',
        web.RTCDataChannelInit(ordered: true),
      ),
    );
    return _gather((await _pc.createOffer().toDart)!);
  }

  Future<String> createAnswer(String offer) async {
    await _pc
        .setRemoteDescription(
          web.RTCSessionDescriptionInit(type: 'offer', sdp: offer),
        )
        .toDart;
    return _gather((await _pc.createAnswer().toDart)!);
  }

  Future<void> acceptAnswer(String answer) async {
    await _pc
        .setRemoteDescription(
          web.RTCSessionDescriptionInit(type: 'answer', sdp: answer),
        )
        .toDart;
  }

  Future<String> candidateKind() async {
    // Only the candidate type is exposed; addresses and SDP are never logged.
    final stats = await _pc.getStats().toDart;
    final rows = <String, Map>{};
    stats.callMethod<JSAny?>(
      'forEach'.toJS,
      ((JSAny value, JSAny key, JSAny _) {
        final row = value.dartify();
        if (row is Map) rows[key.dartify().toString()] = row;
      }).toJS,
    );
    for (final row in rows.values) {
      if (row['type'] == 'transport' &&
          rows[row['selectedCandidatePairId']] is Map) {
        final pair = rows[row['selectedCandidatePairId']]!;
        final local = rows[pair['localCandidateId']];
        final remote = rows[pair['remoteCandidateId']];
        return local?['candidateType'] == 'relay' ||
                remote?['candidateType'] == 'relay'
            ? 'relay'
            : 'direct';
      }
    }
    return 'unknown';
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _fail('连接已取消');
    await _transport?.close();
    _pc.close();
    await _states.close();
  }
}

class _WebChannel implements RtcTextChannel {
  _WebChannel(this.data, this.maximum) {
    data.bufferedAmountLowThreshold = 64 * 1024;
    data.onmessage = ((web.MessageEvent event) {
      if (event.data.isA<JSString>()) {
        _incoming.add((event.data as JSString).toDart);
      }
    }).toJS;
    data.onclose = ((web.Event _) {
      notifyDisconnect();
    }).toJS;
    data.onerror = ((web.Event _) {
      notifyDisconnect();
    }).toJS;
    data.onbufferedamountlow = ((web.Event _) {
      if (_drained != null && !_drained!.isCompleted) _drained!.complete();
    }).toJS;
  }
  final web.RTCDataChannel data;
  final int Function() maximum;
  final _incoming = StreamController<String>.broadcast();
  final _disconnections = StreamController<void>.broadcast();
  bool _closed = false;
  Completer<void>? _drained;
  @override
  int get maxMessageSize => maximum() <= 0 ? rtcMaxFrameBytes : maximum();
  @override
  Stream<String> get incoming => _incoming.stream;
  @override
  Stream<void> get disconnections => _disconnections.stream;
  void notifyDisconnect() {
    if (!_closed) _disconnections.add(null);
    if (_drained != null && !_drained!.isCompleted) _drained!.complete();
  }

  @override
  Future<void> sendText(String text) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (data.bufferedAmount > 256 * 1024 && !_closed) {
      _drained = Completer<void>();
      // Recheck after a short bounded wait: bufferedamountlow may race setup.
      await Future.any<void>([
        _drained!.future,
        Future<void>.delayed(const Duration(milliseconds: 100)),
      ]);
      _drained = null;
      if (DateTime.now().isAfter(deadline)) throw StateError('发送缓冲等待超时');
    }
    if (_closed || data.readyState != 'open') {
      throw StateError('DataChannel 已断开');
    }
    data.send(text.toJS);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    notifyDisconnect();
    _closed = true;
    data.onopen = null;
    data.onmessage = null;
    data.onclose = null;
    data.onerror = null;
    data.onbufferedamountlow = null;
    data.close();
    await _incoming.close();
    await _disconnections.close();
  }
}
