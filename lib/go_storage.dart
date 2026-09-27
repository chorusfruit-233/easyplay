import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_session.dart';
import 'go_ai_settings.dart';

/// One stored game, with the settings it was played under.
///
/// The Go home page lists these, so everything needed to reopen a game exactly
/// as it was left travels together instead of being read back from whichever
/// game happened to be saved last.
class GoSavedRecord {
  const GoSavedRecord({
    required this.id,
    required this.sgf,
    this.vsComputer = false,
    this.humanSide = Side.black,
    this.aiSettings,
  });

  final String id;
  final String sgf;
  final bool vsComputer;
  final Side humanSide;
  final GoAiSettings? aiSettings;

  /// When the game was created, or null for entries whose id is not a timestamp.
  DateTime? get createdAt {
    final micros = int.tryParse(id);
    return micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros);
  }
}

class GoStorage {
  static const _lastSgfKey = 'easyplay.last_go_sgf';
  // Every game, newest first. The library is a library, so it does not drop the
  // oldest entry to make room; 棋谱库 is where they are managed and deleted.
  static const _recordsKey = 'easyplay.go_records';
  static Future<void>? _pending;

  /// Runs writes one after another and keeps a failure from poisoning the queue.
  static Future<T> _serialize<T>(Future<T> Function() action) {
    final result = (_pending ?? Future<void>.value()).then((_) => action());
    final queued = result.then<void>((_) {}, onError: (_, _) {});
    _pending = queued;
    queued.then((_) {
      if (identical(_pending, queued)) _pending = null;
    });
    return result;
  }

  static String _encode(
    String id,
    String sgf,
    bool vsComputer,
    GoAiSettings? aiSettings,
    Side humanSide,
  ) => jsonEncode({
    'id': id,
    'sgf': sgf,
    'vsComputer': vsComputer,
    'humanSide': humanSide.name,
    'ai': (aiSettings ?? const GoAiSettings()).toJson(),
  });

  /// Serialize writes and replace a game's snapshot instead of treating every
  /// move as a new game. Existing raw SGF history remains readable.
  static Future<void> saveLast(
    String sgf, {
    String gameId = 'current',
    bool vsComputer = false,
    GoAiSettings? aiSettings,
    Side humanSide = Side.black,
  }) {
    return _serialize(() async {
      final prefs = await SharedPreferences.getInstance();
      final records = prefs.getStringList(_recordsKey) ?? <String>[];
      records.removeWhere((entry) {
        try {
          return (jsonDecode(entry) as Map)['id'] == gameId;
        } catch (_) {
          return entry == sgf;
        }
      });
      records.insert(
        0,
        _encode(gameId, sgf, vsComputer, aiSettings, humanSide),
      );
      final ok = await prefs.setStringList(_recordsKey, records);
      final last = await prefs.setString(_lastSgfKey, sgf);
      await prefs.setString('easyplay.last_go_id', gameId);
      await prefs.setBool('easyplay.last_go_computer', vsComputer);
      await prefs.setString(
        'easyplay.last_go_ai_settings',
        jsonEncode((aiSettings ?? const GoAiSettings()).toJson()),
      );
      await prefs.setString('easyplay.last_go_human_side', humanSide.name);
      if (!ok || !last) throw StateError('本地存储写入失败');
    });
  }

  /// Adds a game to the library under an id of its own.
  ///
  /// Importing a kifu is not playing it, so the "continue where you left off"
  /// slot is left untouched.
  static Future<GoSavedRecord> addRecord(
    String sgf, {
    bool vsComputer = false,
    GoAiSettings? aiSettings,
    Side humanSide = Side.black,
  }) async {
    final record = GoSavedRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sgf: sgf,
      vsComputer: vsComputer,
      humanSide: humanSide,
      aiSettings: aiSettings,
    );
    await _serialize(() async {
      final prefs = await SharedPreferences.getInstance();
      final records = prefs.getStringList(_recordsKey) ?? <String>[];
      records.removeWhere((entry) => _idOf(entry) == record.id);
      records.insert(
        0,
        _encode(
          record.id,
          record.sgf,
          record.vsComputer,
          record.aiSettings,
          record.humanSide,
        ),
      );
      if (!await prefs.setStringList(_recordsKey, records)) {
        throw StateError('本地存储写入失败');
      }
    });
    return record;
  }

  /// Removes one game, and the resume slot with it when they are the same game.
  static Future<void> deleteRecord(String id) => _serialize(() async {
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.getStringList(_recordsKey) ?? <String>[];
    records.removeWhere((entry) => _idOf(entry) == id);
    if (!await prefs.setStringList(_recordsKey, records)) {
      throw StateError('本地存储写入失败');
    }
    if (prefs.getString('easyplay.last_go_id') != id) return;
    await prefs.remove(_lastSgfKey);
    await prefs.remove('easyplay.last_go_id');
    await prefs.remove('easyplay.last_go_computer');
    await prefs.remove('easyplay.last_go_ai_settings');
    await prefs.remove('easyplay.last_go_human_side');
  });

  /// The id an entry was stored under, or null for the pre-settings format,
  /// which was a bare SGF string with no id at all.
  static String? _idOf(String entry) {
    try {
      return (jsonDecode(entry) as Map)['id'] as String?;
    } catch (_) {
      return null;
    }
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

  static Future<GoAiSettings?> lastAiSettings() async {
    await _pending;
    final raw = (await SharedPreferences.getInstance()).getString(
      'easyplay.last_go_ai_settings',
    );
    if (raw == null) return null;
    try {
      return GoAiSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Side?> lastHumanSide() async {
    await _pending;
    final value = (await SharedPreferences.getInstance()).getString(
      'easyplay.last_go_human_side',
    );
    return Side.values.where((side) => side.name == value).firstOrNull;
  }

  /// Saved games, newest first, with everything needed to reopen one.
  ///
  /// Entries written before the settings were stored per game still load: they
  /// fall back to a record with no opponent, which is the safe reading of "we
  /// do not know who was playing".
  static Future<List<GoSavedRecord>> recentRecords() async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_recordsKey) ?? <String>[])
        .map(_decodeRecord)
        .toList();
  }

  static GoSavedRecord _decodeRecord(String entry) {
    try {
      final map = (jsonDecode(entry) as Map).cast<String, Object?>();
      final ai = map['ai'];
      return GoSavedRecord(
        id: '${map['id'] ?? ''}',
        sgf: '${map['sgf'] ?? ''}',
        vsComputer: map['vsComputer'] == true,
        humanSide:
            Side.values
                .where((side) => side.name == map['humanSide'])
                .firstOrNull ??
            Side.black,
        aiSettings: ai is Map
            ? GoAiSettings.fromJson(ai.cast<String, Object?>())
            : null,
      );
    } catch (_) {
      // A bare SGF string is the pre-settings format.
      return GoSavedRecord(id: '', sgf: entry);
    }
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
    await prefs.remove('easyplay.last_go_ai_settings');
    await prefs.remove('easyplay.last_go_human_side');
  }
}
