import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class GoStorage {
  static const _lastSgfKey = 'easyplay.last_go_sgf';
  static const _recordsKey = 'easyplay.go_records';
  static Future<void>? _pending;

  /// Serialize writes and replace a game's snapshot instead of treating every
  /// move as a new game. Existing raw SGF history remains readable.
  static Future<void> saveLast(
    String sgf, {
    String gameId = 'current',
    bool vsComputer = false,
  }) {
    final write = (_pending ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final records = prefs.getStringList(_recordsKey) ?? <String>[];
      records.removeWhere((entry) {
        try {
          return (jsonDecode(entry) as Map)['id'] == gameId;
        } catch (_) {
          return entry == sgf;
        }
      });
      records.insert(0, jsonEncode({'id': gameId, 'sgf': sgf}));
      final ok = await prefs.setStringList(
        _recordsKey,
        records.take(20).toList(),
      );
      final last = await prefs.setString(_lastSgfKey, sgf);
      await prefs.setString('easyplay.last_go_id', gameId);
      await prefs.setBool('easyplay.last_go_computer', vsComputer);
      if (!ok || !last) throw StateError('本地存储写入失败');
    });
    final queued = write.catchError((Object _) {});
    _pending = queued;
    queued.then((_) {
      if (identical(_pending, queued)) _pending = null;
    });
    return write;
  }

  static Future<String?> loadLast() async {
    await _pending;
    return (await SharedPreferences.getInstance()).getString(_lastSgfKey);
  }

  static Future<String?> lastId() async {
    await _pending;
    return (await SharedPreferences.getInstance()).getString(
      'easyplay.last_go_id',
    );
  }

  static Future<bool> lastComputerMode() async {
    await _pending;
    return (await SharedPreferences.getInstance()).getBool(
          'easyplay.last_go_computer',
        ) ??
        false;
  }

  static Future<List<String>> records() async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_recordsKey) ?? <String>[]).map((entry) {
      try {
        return (jsonDecode(entry) as Map)['sgf'] as String;
      } catch (_) {
        return entry;
      }
    }).toList();
  }

  static Future<void> clear() async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSgfKey);
    await prefs.remove(_recordsKey);
    await prefs.remove('easyplay.last_go_id');
    await prefs.remove('easyplay.last_go_computer');
  }
}
