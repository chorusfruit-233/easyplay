import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum GoEngineBackend {
  cpu,
  opencl,
  tflite;

  String get label => switch (this) {
    GoEngineBackend.cpu => 'CPU',
    GoEngineBackend.opencl => 'OpenCL',
    GoEngineBackend.tflite => 'TFLite Mobile',
  };
}

/// State of the device-specific OpenCL tuning snapshot.
///
/// A profile can be saved before tuning has run. Runtime code should only
/// start an OpenCL engine when the state is [ready].
enum GoOpenClTuningState {
  unknown,
  required,
  tuning,
  ready,
  failed;

  String get label => switch (this) {
    GoOpenClTuningState.unknown => '未检测',
    GoOpenClTuningState.required => '需要调优',
    GoOpenClTuningState.tuning => '调优中',
    GoOpenClTuningState.ready => '已调优',
    GoOpenClTuningState.failed => '调优失败',
  };
}

/// A rank-scoped block of KataGo configuration overrides.
///
/// Ranks use KataGo's convention: positive values are kyu; 0 is 1d and -8 is 9d. A global rule has no rank bounds and is the fallback rule.
class GoEngineOverrideRule {
  final String id;
  final String displayName;
  final int? rankMin;
  final int? rankMax;
  final String configText;

  const GoEngineOverrideRule({
    required this.id,
    required this.displayName,
    this.rankMin,
    this.rankMax,
    this.configText = '',
  });

  bool get isGlobal => rankMin == null && rankMax == null;

  bool matches(int rank) =>
      isGlobal ||
      (rankMin != null &&
          rankMax != null &&
          rank <= rankMin! &&
          rank >= rankMax!);

  Map<String, Object> toJson() {
    final result = <String, Object>{'id': id, 'displayName': displayName};
    if (rankMin != null) result['rankMin'] = rankMin!;
    if (rankMax != null) result['rankMax'] = rankMax!;
    if (configText.trim().isNotEmpty) result['configText'] = configText;
    return result;
  }

  factory GoEngineOverrideRule.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final displayName = json['displayName'];
    final rankMin = json['rankMin'];
    final rankMax = json['rankMax'];
    final configText = json['configText'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('override 规则缺少 id');
    }
    if (displayName is! String || displayName.trim().isEmpty) {
      throw const FormatException('override 规则缺少 displayName');
    }
    if ((rankMin == null) != (rankMax == null)) {
      throw FormatException('override 规则 $id 的 rank 范围不完整');
    }
    if (rankMin is! int? || rankMax is! int?) {
      throw FormatException('override 规则 $id 的 rank 必须是整数');
    }
    if ((rankMin ?? 20) > 20 || (rankMax ?? -8) < -8) {
      throw FormatException('override 规则 $id 的段位超出 20k 至 9d');
    }
    if (rankMin != null && rankMax != null && rankMin < rankMax) {
      throw FormatException('override 规则 $id 的 rank 范围反向');
    }
    if (configText != null && configText is! String) {
      throw FormatException('override 规则 $id 的 configText 必须是文本');
    }
    return GoEngineOverrideRule(
      id: id,
      displayName: displayName,
      rankMin: rankMin,
      rankMax: rankMax,
      configText: configText as String? ?? '',
    );
  }

  static void validateList(
    List<GoEngineOverrideRule> rules, {
    String fieldName = 'overrideRules',
  }) {
    final ids = <String>{};
    var globals = 0;
    for (final rule in rules) {
      if (!ids.add(rule.id)) {
        throw ArgumentError('$fieldName 中存在重复规则 id：${rule.id}');
      }
      if (rule.id.trim().isEmpty || rule.displayName.trim().isEmpty) {
        throw ArgumentError('override 规则名称和 id 不能为空');
      }
      if ((rule.rankMin == null) != (rule.rankMax == null)) {
        throw ArgumentError('override 规则的段位范围不完整');
      }
      if ((rule.rankMin ?? 20) > 20 || (rule.rankMax ?? -8) < -8) {
        throw ArgumentError('override 段位范围必须在 20k 至 9d 之间');
      }
      if (rule.isGlobal) {
        globals++;
      } else if (rule.rankMin! < rule.rankMax!) {
        throw ArgumentError('override 规则 ${rule.id} 的 rank 范围反向');
      }
      GoEngineLibrary.validateOverrides(rule.configText);
    }
    if (globals > 1) {
      throw ArgumentError('$fieldName 最多只能有一个 global 规则');
    }
    final ranged = rules.where((rule) => !rule.isGlobal).toList();
    for (var i = 0; i < ranged.length; i++) {
      for (var j = i + 1; j < ranged.length; j++) {
        final a = ranged[i];
        final b = ranged[j];
        if (a.rankMax! <= b.rankMin! && b.rankMax! <= a.rankMin!) {
          throw ArgumentError('$fieldName 存在重叠的 rank 范围');
        }
      }
    }
  }

  static GoEngineOverrideRule? resolve(
    List<GoEngineOverrideRule> rules,
    int rank,
  ) {
    final matches = rules.where((rule) => rule.matches(rank)).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => _width(a).compareTo(_width(b)));
    return matches.first;
  }

  static int _width(GoEngineOverrideRule rule) =>
      rule.isGlobal ? 1 << 30 : rule.rankMin! - rule.rankMax!;
}

class GoEngineProfile {
  final String id;
  final String name;
  final int maxTimeSeconds;
  final int searchThreads;
  final String configOverrides;
  final String customConfig;
  final String? modelId;
  final String? humanModelId;
  final GoEngineBackend backend;
  final int? openclGpuIdx;
  final String? openclLibraryName;
  final String? openclTuningId;
  final String? openclTuningPlan;
  final List<String> openclTunedSnapshotKeys;
  final GoOpenClTuningState openclTuningState;
  final List<GoEngineOverrideRule> overrideRules;
  final List<GoEngineOverrideRule> humanOverrideRules;

  const GoEngineProfile({
    required this.id,
    required this.name,
    this.maxTimeSeconds = 3,
    this.searchThreads = 2,
    this.configOverrides = '',
    this.customConfig = '',
    this.modelId,
    this.humanModelId,
    this.backend = GoEngineBackend.cpu,
    this.openclGpuIdx,
    this.openclLibraryName,
    this.openclTuningId,
    this.openclTuningPlan,
    this.openclTunedSnapshotKeys = const <String>[],
    this.openclTuningState = GoOpenClTuningState.unknown,
    this.overrideRules = const <GoEngineOverrideRule>[],
    this.humanOverrideRules = const <GoEngineOverrideRule>[],
  });

  static const builtIn = GoEngineProfile(id: 'default', name: 'KataGo');

  Map<String, Object> toJson() {
    final result = <String, Object>{
      'id': id,
      'name': name,
      'maxTimeSeconds': maxTimeSeconds,
      'searchThreads': searchThreads,
      'configOverrides': configOverrides,
      'customConfig': customConfig,
      'modelId': ?modelId,
      'humanModelId': ?humanModelId,
      'backend': backend.name,
    };
    if (openclGpuIdx != null) result['openclGpuIdx'] = openclGpuIdx!;
    if (openclLibraryName != null) {
      result['openclLibraryName'] = openclLibraryName!;
    }
    if (openclTuningId != null) result['openclTuningId'] = openclTuningId!;
    if (openclTuningPlan != null) {
      result['openclTuningPlan'] = openclTuningPlan!;
    }
    if (openclTunedSnapshotKeys.isNotEmpty) {
      result['openclTunedSnapshotKeys'] = openclTunedSnapshotKeys;
    }
    result['openclTuningState'] = openclTuningState.name;
    if (overrideRules.isNotEmpty) {
      result['overrideRules'] = overrideRules
          .map((rule) => rule.toJson())
          .toList();
    }
    if (humanOverrideRules.isNotEmpty) {
      result['humanOverrideRules'] = humanOverrideRules
          .map((rule) => rule.toJson())
          .toList();
    }
    return result;
  }

  factory GoEngineProfile.fromJson(Map<String, Object?> json) =>
      GoEngineProfile(
        id: json['id']! as String,
        name: json['name']! as String,
        maxTimeSeconds: json['maxTimeSeconds'] as int? ?? 3,
        searchThreads: json['searchThreads'] as int? ?? 2,
        configOverrides: json['configOverrides'] as String? ?? '',
        customConfig: json['customConfig'] as String? ?? '',
        modelId: json['modelId'] as String?,
        humanModelId: json['humanModelId'] as String?,
        backend: GoEngineBackend.values.firstWhere(
          (value) => value.name == json['backend'],
          orElse: () => GoEngineBackend.cpu,
        ),
        openclGpuIdx: json['openclGpuIdx'] as int?,
        openclLibraryName: json['openclLibraryName'] as String?,
        openclTuningId: json['openclTuningId'] as String?,
        openclTuningPlan: json['openclTuningPlan'] as String?,
        openclTunedSnapshotKeys: _stringList(json['openclTunedSnapshotKeys']),
        openclTuningState: GoOpenClTuningState.values.firstWhere(
          (value) => value.name == json['openclTuningState'],
          orElse: () => GoOpenClTuningState.unknown,
        ),
        overrideRules: _ruleList(json['overrideRules']),
        humanOverrideRules: _ruleList(json['humanOverrideRules']),
      );

  GoEngineProfile copyWith({
    String? name,
    GoOpenClTuningState? tuningState,
    List<String>? snapshotKeys,
  }) => GoEngineProfile.fromJson({
    ...toJson(),
    'name': ?name,
    if (tuningState != null) 'openclTuningState': tuningState.name,
    'openclTunedSnapshotKeys': ?snapshotKeys,
  });

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];

  static List<GoEngineOverrideRule> _ruleList(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map(
              (entry) =>
                  GoEngineOverrideRule.fromJson(entry.cast<String, Object?>()),
            )
            .toList(growable: false)
      : const <GoEngineOverrideRule>[];

  bool get openclTuningReady =>
      backend != GoEngineBackend.opencl ||
      openclTuningState == GoOpenClTuningState.ready;

  GoEngineOverrideRule? resolveOverride({
    required int rank,
    bool humanStyle = false,
  }) => GoEngineOverrideRule.resolve(
    humanStyle ? humanOverrideRules : overrideRules,
    rank,
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
        _validate(profile);
        profiles.removeWhere((entry) => entry.id == profile.id);
        profiles.add(profile);
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
    rows.add(jsonEncode(profile.toJson()));
    await prefs.setStringList(_profilesKey, rows);
  }

  static void validateOverrides(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (!RegExp(
        r'^[A-Za-z][A-Za-z0-9_]*\s*=\s*[^\r\n]*$',
      ).hasMatch(trimmed)) {
        throw ArgumentError('无效的 KataGo 参数行：$line');
      }
    }
  }

  static Future<void> resetBuiltIn() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(_profilesKey) ?? <String>[];
    rows.removeWhere((row) {
      try {
        return (jsonDecode(row) as Map)['id'] == GoEngineProfile.builtIn.id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_profilesKey, rows);
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
    if (profile.openclGpuIdx != null && profile.openclGpuIdx! < 0) {
      throw ArgumentError('OpenCL GPU 编号不能为负数');
    }
    if (profile.backend == GoEngineBackend.opencl &&
        profile.openclLibraryName != null &&
        profile.openclLibraryName!.trim().isEmpty) {
      throw ArgumentError('OpenCL 动态库名称不能为空');
    }
    validateOverrides(profile.configOverrides);
    validateOverrides(profile.customConfig);
    GoEngineOverrideRule.validateList(profile.overrideRules);
    GoEngineOverrideRule.validateList(
      profile.humanOverrideRules,
      fieldName: 'humanOverrideRules',
    );
    if (profile.backend == GoEngineBackend.opencl &&
        profile.openclTuningState == GoOpenClTuningState.ready &&
        profile.openclTunedSnapshotKeys.isEmpty &&
        profile.openclTuningPlan == null) {
      throw ArgumentError('OpenCL 配置标记为已调优但缺少调优快照');
    }
  }
}
