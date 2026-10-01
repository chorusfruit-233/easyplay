import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'lan_protocol.dart';

const rtcMaxMessageBytes = 4 * 1024 * 1024;
const rtcMaxFrameBytes = 16 * 1024;

String rtcSecret() {
  final random = Random.secure();
  return base64Url
      .encode(List.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

/// JSON + base64 keeps frames interoperable and bounds UTF-8 bytes on the wire.
Iterable<String> rtcFrames(
  LanMessage message, {
  int maxFrameBytes = rtcMaxFrameBytes,
}) sync* {
  final bytes = utf8.encode(message.encode());
  if (bytes.length > rtcMaxMessageBytes) {
    throw const FormatException('同步数据超过 4 MiB');
  }
  final limit = min(maxFrameBytes, rtcMaxFrameBytes);
  if (limit < 1024) throw const FormatException('DataChannel 消息上限过小');
  final chunkSize = ((limit - 512) * 3 ~/ 4);
  final total = (bytes.length / chunkSize).ceil();
  final id = rtcSecret();
  final digest = sha256.convert(bytes).toString();
  for (var index = 0; index < total; index++) {
    yield jsonEncode({
      'frame': 1,
      'transferId': id,
      'index': index,
      'total': total,
      'byteLength': bytes.length,
      'digest': digest,
      'data': base64.encode(
        bytes.sublist(
          index * chunkSize,
          min((index + 1) * chunkSize, bytes.length),
        ),
      ),
    });
  }
}

class RtcReassembler {
  RtcReassembler({this.timeout = const Duration(seconds: 15)});
  final Duration timeout;
  final _pending = <String, _Transfer>{};
  int get pendingCount => _pending.length;
  int get reservedBytes => _pending.values.fold(0, (sum, t) => sum + t.length);

  /// Caller invokes periodically and asks its replica to synchronize on loss.
  bool expire([DateTime? at]) {
    final now = at ?? DateTime.now();
    final expired = _pending.entries
        .where((e) => now.difference(e.value.created) > timeout)
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      _pending.remove(id);
    }
    return expired.isNotEmpty;
  }

  LanMessage? receive(String raw) {
    String? id;
    try {
      if (utf8.encode(raw).length > rtcMaxFrameBytes) {
        throw const FormatException('分片过大');
      }
      final frame = jsonDecode(raw);
      if (frame is! Map ||
          frame['frame'] is! int ||
          frame['frame'] != 1 ||
          frame['transferId'] is! String) {
        throw const FormatException('无效分片');
      }
      id = frame['transferId'] as String;
      if (id.length > 64 ||
          id.isEmpty ||
          frame['digest'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(frame['digest'] as String)) {
        throw const FormatException('无效传输标识');
      }
      final index = frame['index'],
          total = frame['total'],
          length = frame['byteLength'];
      if (index is! int ||
          total is! int ||
          length is! int ||
          length < 1 ||
          length > rtcMaxMessageBytes ||
          total < 1 ||
          total > 8192 ||
          index < 0 ||
          index >= total ||
          frame['data'] is! String) {
        throw const FormatException('无效分片长度');
      }
      if (!_pending.containsKey(id)) {
        if (_pending.length >= 4 || reservedBytes + length > 8 * 1024 * 1024) {
          throw const FormatException('未完成传输过多');
        }
        _pending[id] = _Transfer(total, length, frame['digest'] as String);
      }
      final t = _pending[id]!;
      if (t.total != total ||
          t.length != length ||
          t.digest != frame['digest'] ||
          t.parts.containsKey(index)) {
        throw const FormatException('重复或冲突分片');
      }
      final bytes = base64.decode(frame['data'] as String);
      if (bytes.isEmpty || t.received + bytes.length > length) {
        throw const FormatException('分片数据超过声明长度');
      }
      t.parts[index] = bytes;
      t.received += bytes.length;
      if (t.parts.length != total) return null;
      _pending.remove(id);
      final data = BytesBuilder(copy: false);
      for (var i = 0; i < total; i++) {
        data.add(t.parts[i]!);
      }
      final assembled = data.takeBytes();
      if (assembled.length != length ||
          sha256.convert(assembled).toString() != t.digest) {
        throw const FormatException('分片校验失败');
      }
      return LanMessage.decode(utf8.decode(assembled));
    } catch (_) {
      if (id != null) _pending.remove(id);
      rethrow;
    }
  }

  void clear() => _pending.clear();
}

class _Transfer {
  _Transfer(this.total, this.length, this.digest);
  final int total, length;
  final String digest;
  final DateTime created = DateTime.now();
  final parts = <int, Uint8List>{};
  int received = 0;
}
