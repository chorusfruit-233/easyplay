import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'draughts_record.dart';

class DraughtsSavedRecord {
  const DraughtsSavedRecord({
    required this.id,
    required this.variant,
    required this.record,
    required this.kind,
    required this.localSide,
    required this.createdAt,
  });
  final String id;
  final String variant;
  final DraughtsRecord record;
  final DraughtsGameKind kind;
  final String? localSide;
  final DateTime createdAt;
}

class DraughtsStorage {
  static const _key = 'easyplay.draughts.records.v1';

  static Future<void> _writeQueue = Future<void>.value();

  static Future<List<DraughtsRecord>> list() async {
    await _writeQueue;
    return _readList();
  }

  static Future<List<DraughtsRecord>> _readList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('invalid saved draughts games');
    }
    return decoded.map(DraughtsRecord.fromJson).toList();
  }

  static Future<void> save(DraughtsRecord record) {
    final operation = _writeQueue.then((_) => _save(record));
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  static Future<void> _save(DraughtsRecord record) async {
    final records = await _readList();
    final id = record.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final saved = DraughtsRecord(
      id: id,
      variant: record.variant,
      moves: record.moves,
      kind: record.kind,
      localSide: record.localSide,
      createdAt: record.createdAt,
      result: record.result,
      sessionState: record.sessionState,
    );
    final next = [saved, ...records.where((item) => item.id != id)].take(500);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> delete(String id) {
    final operation = _writeQueue.then((_) => _delete(id));
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  static Future<void> _delete(String id) async {
    final records = await _readList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(
        records
            .where((item) => item.id != id)
            .map((item) => item.toJson())
            .toList(),
      ),
    );
  }
}
