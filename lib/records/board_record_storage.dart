import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'board_record.dart';

class BoardRecordStorage {
  static String key(BoardRecordGame game) => 'easyplay.${game.name}.records.v1';
  static final _queues = <BoardRecordGame, Future<void>>{};

  static Future<List<BoardGameRecord>> list(BoardRecordGame game) async {
    await _queues[game];
    return _read(game);
  }

  static Future<List<BoardGameRecord>> _read(BoardRecordGame game) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key(game));
    if (raw == null) return [];
    final data = jsonDecode(raw);
    if (data is! List) throw const FormatException('无法读取棋谱库');
    final records = data.map(BoardGameRecord.fromJson).toList();
    if (records.any((record) => record.game != game)) {
      throw const FormatException('棋谱库棋种不匹配');
    }
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records;
  }

  static Future<void> _enqueue(
    BoardRecordGame game,
    Future<void> Function() action,
  ) {
    final operation = (_queues[game] ?? Future<void>.value()).then(
      (_) => action(),
    );
    late final Future<void> queued;
    queued = operation.catchError((Object _) {}).whenComplete(() {
      if (identical(_queues[game], queued)) _queues.remove(game);
    });
    _queues[game] = queued;
    return operation;
  }

  static Future<void> _write(
    BoardRecordGame game,
    List<BoardGameRecord> records,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key(game),
      jsonEncode(records.map((record) => record.toJson()).toList()),
    )) {
      throw StateError('本地存储写入失败');
    }
  }

  static Future<void> save(BoardGameRecord record) =>
      _enqueue(record.game, () async {
        final records = await _read(record.game);
        await _write(record.game, [
          record,
          ...records.where((old) => old.id != record.id),
        ]);
      });

  static Future<void> delete(BoardRecordGame game, String id) =>
      _enqueue(game, () async {
        final records = await _read(game);
        await _write(game, records.where((record) => record.id != id).toList());
      });
}
