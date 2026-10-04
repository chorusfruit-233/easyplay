import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../game_session.dart' show Side;
import 'gomoku_ai_level.dart';
import 'gomoku_session.dart';

class GomokuRecord {
  GomokuRecord({
    required this.id,
    required this.createdAt,
    required GomokuSession session,
    this.aiLevel,
    this.humanSide = Side.black,
  }) : _state = session.fork().toJson();

  final String id;
  final DateTime createdAt;
  final GomokuAiLevel? aiLevel;
  final Side humanSide;
  final Map<String, Object?> _state;

  GomokuSession restore() => GomokuSession.fromJson(_state);
  int get moveCount => (_state['moves'] as List).length;
  GomokuVariant get variant => GomokuVariant.fromName(_state['variant']);
  bool get gameOver => _state['gameOver'] == true;
  String get resultLabel => restore().resultLabel;

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'aiLevel': aiLevel?.name,
    'humanSide': humanSide.name,
    'session': _state,
  };

  factory GomokuRecord.fromJson(Object? json) {
    if (json is! Map ||
        json['version'] != 1 ||
        json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        json['createdAt'] is! String) {
      throw const FormatException('无效的五子棋存档');
    }
    final side = switch (json['humanSide']) {
      'black' => Side.black,
      'white' => Side.white,
      _ => null,
    };
    if (side == null) throw const FormatException('无效的执棋方');
    final levelName = json['aiLevel'];
    final level = GomokuAiLevel.values
        .where((value) => value.name == levelName)
        .firstOrNull;
    if (levelName != null && level == null) {
      throw const FormatException('无效的五子棋 AI 难度');
    }
    return GomokuRecord(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      session: GomokuSession.fromJson(json['session']),
      aiLevel: level,
      humanSide: side,
    );
  }
}

class GomokuStorage {
  static const key = 'easyplay.gomoku.records.v1';
  static Future<void>? _queue;

  static Future<List<GomokuRecord>> list() async {
    final pending = _queue;
    if (pending != null) await pending;
    return _read();
  }

  static Future<List<GomokuRecord>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(key);
    if (raw is! String) return [];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return [];
    }
    if (decoded is! List) return [];
    final result = <GomokuRecord>[];
    final ids = <String>{};
    for (final item in decoded.take(100)) {
      try {
        final record = GomokuRecord.fromJson(item);
        if (ids.add(record.id)) result.add(record);
      } on FormatException {
        // A corrupt or newer record must not hide the remaining saved games.
      } on ArgumentError {
        // Reject invalid imported coordinates and dates without breaking home.
      }
    }
    return result;
  }

  static Future<void> _enqueue(Future<void> Function() operation) {
    final result = (_queue ?? Future<void>.value()).then((_) => operation());
    late Future<void> safe;
    safe = result.catchError((Object _) {}).whenComplete(() {
      if (identical(_queue, safe)) _queue = null;
    });
    _queue = safe;
    return result;
  }

  static Future<void> save(GomokuRecord record) => _enqueue(() async {
    final records = await _read();
    final next = [record, ...records.where((item) => item.id != record.id)];
    await _write(next.take(100));
  });

  static Future<void> delete(String id) => _enqueue(() async {
    final records = await _read();
    await _write(records.where((item) => item.id != id));
  });

  static Future<void> _write(Iterable<GomokuRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      key,
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
    if (!saved) throw StateError('无法写入五子棋存档');
  }
}
