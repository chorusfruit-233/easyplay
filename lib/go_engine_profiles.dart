import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class GoEngineProfile {
  final String id;
  final String name;
  final int maxTimeSeconds;
  final int searchThreads;
  final String configOverrides;

  const GoEngineProfile({
    required this.id,
    required this.name,
    this.maxTimeSeconds = 3,
    this.searchThreads = 2,
    this.configOverrides = '',
  });

  static const builtIn = GoEngineProfile(id: 'default', name: 'KataGo');

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'maxTimeSeconds': maxTimeSeconds,
    'searchThreads': searchThreads,
    'configOverrides': configOverrides,
  };

  factory GoEngineProfile.fromJson(Map<String, Object?> json) =>
      GoEngineProfile(
        id: json['id']! as String,
        name: json['name']! as String,
        maxTimeSeconds: json['maxTimeSeconds'] as int? ?? 3,
        searchThreads: json['searchThreads'] as int? ?? 2,
        configOverrides: json['configOverrides'] as String? ?? '',
      );
}

class GoEngineLibrary {
  static const _profilesKey = 'easyplay.katago_engine_profiles';
  static const _activeKey = 'easyplay.katago_active_engine';

  static Future<List<GoEngineProfile>> available() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(_profilesKey) ?? const <String>[];
    final profiles = <GoEngineProfile>[GoEngineProfile.builtIn];
    for (final row in rows) {
      try {
        final profile = GoEngineProfile.fromJson(
          (jsonDecode(row) as Map).cast<String, Object?>(),
        );
        if (profile.id != GoEngineProfile.builtIn.id) profiles.add(profile);
      } catch (_) {
        // Keep valid profiles available if a saved row is damaged.
      }
    }
    return profiles;
  }

  static Future<String> activeId() async {
    final id = (await SharedPreferences.getInstance()).getString(_activeKey);
    final profiles = await available();
    return profiles.any((profile) => profile.id == id)
        ? id!
        : GoEngineProfile.builtIn.id;
  }

  static Future<void> setActive(String id) async {
    if (!(await available()).any((profile) => profile.id == id)) {
      throw ArgumentError.value(id, 'id', 'KataGo 引擎配置不存在');
    }
    await (await SharedPreferences.getInstance()).setString(_activeKey, id);
  }

  static Future<GoEngineProfile> byId(String id) async =>
      (await available()).firstWhere(
        (profile) => profile.id == id,
        orElse: () => GoEngineProfile.builtIn,
      );

  static Future<void> save(GoEngineProfile profile) async {
    _validate(profile);
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(_profilesKey) ?? <String>[];
    rows.removeWhere((row) {
      try {
        return (jsonDecode(row) as Map)['id'] == profile.id;
      } catch (_) {
        return false;
      }
    });
    if (profile.id != GoEngineProfile.builtIn.id) {
      rows.add(jsonEncode(profile.toJson()));
    }
    await prefs.setStringList(_profilesKey, rows);
  }

  static void validateOverrides(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9]*\s*=\s*[^\r\n]*$').hasMatch(trimmed)) {
        throw ArgumentError('无效的 KataGo 参数行：$line');
      }
    }
  }

  static Future<void> remove(String id) async {
    if (id == GoEngineProfile.builtIn.id) {
      throw ArgumentError('内置 KataGo 配置不能删除');
    }
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(_profilesKey) ?? <String>[];
    rows.removeWhere((row) {
      try {
        return (jsonDecode(row) as Map)['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_profilesKey, rows);
    if (prefs.getString(_activeKey) == id) {
      await prefs.setString(_activeKey, GoEngineProfile.builtIn.id);
    }
  }

  static void _validate(GoEngineProfile profile) {
    if (profile.id.trim().isEmpty || profile.name.trim().isEmpty) {
      throw ArgumentError('引擎名称不能为空');
    }
    if (profile.maxTimeSeconds < 0 || profile.maxTimeSeconds > 120) {
      throw ArgumentError('最大思考时间需为0至120秒');
    }
    if (profile.searchThreads < 1 || profile.searchThreads > 16) {
      throw ArgumentError('搜索线程数需为1至16');
    }
    validateOverrides(profile.configOverrides);
  }
}
