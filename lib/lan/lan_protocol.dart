import 'dart:convert';

import '../game_session.dart';

const lanProtocolVersion = 2;
const lanMaxEvents = 20000;

/// Requests propose the next seq; only the authority assigns/broadcasts it.
/// Handshakes, heartbeat, rejection and synchronization do not consume seq.
enum LanMessageType {
  hello,
  helloAck,
  matchStart,
  stateRequest,
  stateSync,
  move,
  pass,
  resign,
  rejected,
  undoRequest,
  undoAccept,
  undoReject,
  scoreProposal,
  scoreAccept,
  scoreCounter,
  ping,
  pong,
}

class LanMessage {
  LanMessage(this.type, this.seq, [Map<String, Object?> body = const {}])
    : _body = jsonEncode(body) {
    if (seq < 0 || seq > lanMaxEvents) {
      throw const FormatException('无效的联机序列号');
    }
    _validate();
  }

  final LanMessageType type;
  final int seq;
  // Serialize once to own the payload: callers cannot mutate accepted events.
  final String _body;
  Map<String, Object?> get body =>
      (jsonDecode(_body) as Map).cast<String, Object?>();
  String encode() => jsonEncode(toWire());
  Map<String, Object?> toWire() => {...body, 'type': type.name, 'seq': seq};

  factory LanMessage.decode(String raw) {
    if (raw.length > 4 * 1024 * 1024) {
      throw const FormatException('联机消息过大');
    }
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('联机消息必须是对象');
    }
    return LanMessage.fromWire(value);
  }

  factory LanMessage.fromWire(Map<String, Object?> wire) {
    final type = LanMessageType.values
        .where((type) => type.name == wire['type'])
        .firstOrNull;
    if (type == null || wire['seq'] is! int) {
      throw const FormatException('未知消息或无效序列号');
    }
    final body = Map<String, Object?>.of(wire)
      ..remove('type')
      ..remove('seq');
    return LanMessage(type, wire['seq']! as int, body);
  }

  Side get side => parseSide(body['side']);
  static Side parseSide(Object? raw) => switch (raw) {
    'B' => Side.black,
    'W' => Side.white,
    _ => throw const FormatException('无效的执棋方'),
  };
  static String sideCode(Side side) => side == Side.black ? 'B' : 'W';

  static Cell parseCell(Object? value) {
    if (value is! List ||
        value.length != 2 ||
        value.any((v) => v is! int || v < 0 || v >= 19)) {
      throw const FormatException('无效的棋盘坐标');
    }
    return Cell(value[0] as int, value[1] as int);
  }

  static Map<String, Object?> configToWire(GoConfig config) => {
    'boardSize': config.boardSize,
    'rules': config.rules.name,
    'komi': config.komi,
    'handicap': config.handicap,
  };

  static GoConfig parseConfig(Map<String, Object?> body) {
    final size = body['boardSize'];
    final handicap = body['handicap'];
    final komi = body['komi'];
    final rules = GoRuleSet.values
        .where((v) => v.name == body['rules'])
        .firstOrNull;
    if (size is! int ||
        ![9, 13, 19].contains(size) ||
        handicap is! int ||
        ![0, 2, 3, 4, 5, 6, 7, 8, 9].contains(handicap) ||
        komi is! num ||
        !komi.isFinite ||
        komi < -100 ||
        komi > 100 ||
        rules == null) {
      throw const FormatException('联机棋盘与规则无效');
    }
    return GoConfig(
      boardSize: size,
      rules: rules,
      komi: komi.toDouble(),
      handicap: handicap,
    );
  }

  void _validate() {
    final data = body;
    void integer(String key) {
      if (data[key] is! int ||
          (data[key]! as int) < 0 ||
          (data[key]! as int) > lanMaxEvents) {
        throw FormatException('无效的 $key');
      }
    }

    void string(String key, int limit) {
      if (data[key] is! String ||
          (data[key]! as String).isEmpty ||
          (data[key]! as String).length > limit) {
        throw FormatException('无效的 $key');
      }
    }

    switch (type) {
      case LanMessageType.hello:
        integer('roomVersion');
        if (data['roomVersion'] != lanProtocolVersion) {
          throw const FormatException('联机协议版本不兼容');
        }
        parseConfig(data);
        string('token', 256);
        if (data['resumeSide'] != null) parseSide(data['resumeSide']);
      case LanMessageType.helloAck:
        parseSide(data['assignedSide']);
        if (data['started'] is! bool) {
          throw const FormatException('无效的房间状态');
        }
      case LanMessageType.matchStart:
        if (data.isNotEmpty) throw const FormatException('无效的开始消息');
      case LanMessageType.stateRequest:
        integer('lastSeq');
      case LanMessageType.stateSync:
        integer('roomVersion');
        parseConfig(data);
        final events = data['events'];
        if (events is! List ||
            events.length > lanMaxEvents ||
            events.length != seq) {
          throw const FormatException('无效的同步事件数');
        }
        // State sync contains a complete authoritative log, including undo and
        // score negotiations. A move-only suffix cannot restore those states.
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          if (event is! Map<String, dynamic> ||
              !eventTypes.any((type) => type.name == event['type']) ||
              event['seq'] != i + 1) {
            throw const FormatException('同步事件不连续');
          }
          LanMessage.fromWire(event);
        }
      case LanMessageType.move:
        parseSide(data['side']);
        parseCell(data['cell']);
      case LanMessageType.pass:
      case LanMessageType.resign:
      case LanMessageType.undoRequest:
        parseSide(data['side']);
      case LanMessageType.undoAccept:
      case LanMessageType.undoReject:
      case LanMessageType.scoreAccept:
        parseSide(data['side']);
        integer('requestSeq');
        if (type == LanMessageType.undoReject) string('reason', 256);
      case LanMessageType.scoreProposal:
      case LanMessageType.scoreCounter:
        parseSide(data['side']);
        if (type == LanMessageType.scoreCounter) integer('requestSeq');
        final stones = data['deadStones'];
        if (stones is! List || stones.length > 361) {
          throw const FormatException('无效的死子列表');
        }
        for (final cell in stones) {
          parseCell(cell);
        }
      case LanMessageType.rejected:
        string('reason', 256);
      case LanMessageType.ping:
      case LanMessageType.pong:
        string('nonce', 128);
    }
  }

  static const eventTypes = {
    LanMessageType.move,
    LanMessageType.pass,
    LanMessageType.resign,
    LanMessageType.undoRequest,
    LanMessageType.undoAccept,
    LanMessageType.undoReject,
    LanMessageType.scoreProposal,
    LanMessageType.scoreAccept,
    LanMessageType.scoreCounter,
  };
}
