import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'go_engine_profiles.dart';

/// A human-style KataGo network and the profile name it expects in
/// `humanSLProfile`. The model is kept separate from the regular engine
/// profile because KataGo loads it with `-human-model`.
class GoHumanProfile {
  final String id;
  final String name;
  final String? modelId;
  final String? modelUrl;
  final String? humanSLProfile;

  const GoHumanProfile({
    required this.id,
    required this.name,
    this.modelId,
    this.modelUrl,
    this.humanSLProfile,
  });

  Map<String, Object> toJson() {
    final result = <String, Object>{'id': id, 'name': name};
    if (modelId != null) result['modelId'] = modelId!;
    if (modelUrl != null) result['modelUrl'] = modelUrl!;
    if (humanSLProfile != null) {
      result['humanSLProfile'] = humanSLProfile!;
    }
    return result;
  }

  factory GoHumanProfile.fromJson(Map<String, Object?> json) => GoHumanProfile(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    modelId: json['modelId'] as String?,
    modelUrl: json['modelUrl'] as String?,
    humanSLProfile: json['humanSLProfile'] as String?,
  );

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('人类棋风配置缺少 $key');
    }
    return value;
  }
}

/// One rank range from KataGo's engine_override_defaults.json.
///
/// KataGo rank values use positive numbers for kyu and negative numbers for
/// dan. For example, 20 through -3 means 20k through 4d.
class GoHumanOverrideRule {
  final String id;
  final String displayName;
  final int? rankMin;
  final int? rankMax;

  const GoHumanOverrideRule({
    required this.id,
    required this.displayName,
    this.rankMin,
    this.rankMax,
  });

  bool get isGlobal => rankMin == null && rankMax == null;

  bool matches(int rank) {
    if (isGlobal) return true;
    return rankMin != null &&
        rankMax != null &&
        rank <= rankMin! &&
        rank >= rankMax!;
  }

  Map<String, Object> toJson() {
    final result = <String, Object>{'id': id, 'displayName': displayName};
    if (rankMin != null) result['rankMin'] = rankMin!;
    if (rankMax != null) result['rankMax'] = rankMax!;
    return result;
  }

  factory GoHumanOverrideRule.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final displayName = json['displayName'];
    final rankMin = json['rankMin'];
    final rankMax = json['rankMax'];
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
    if (rankMin != null && rankMax != null && rankMin < rankMax) {
      throw FormatException('override 规则 $id 的 rank 范围反向');
    }
    return GoHumanOverrideRule(
      id: id,
      displayName: displayName,
      rankMin: rankMin,
      rankMax: rankMax,
    );
  }
}

class GoHumanOverrideCatalog {
  static const defaultsAsset = 'assets/katago/engine_override_defaults.json';
  static const overridesAssetPrefix = 'assets/katago/engine_overrides/';

  final int version;
  final List<GoHumanOverrideRule> normalRules;
  final List<GoHumanOverrideRule> humanRules;

  const GoHumanOverrideCatalog({
    required this.version,
    required this.normalRules,
    required this.humanRules,
  });

  static Future<GoHumanOverrideCatalog> load() async {
    final source = await rootBundle.loadString(defaultsAsset);
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('override defaults 不是对象');
    return GoHumanOverrideCatalog.fromJson(decoded.cast<String, Object?>());
  }

  factory GoHumanOverrideCatalog.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! int || version < 1) {
      throw const FormatException('无效的 override defaults 版本');
    }
    return GoHumanOverrideCatalog(
      version: version,
      normalRules: _rules(json['normalRules'], 'normalRules'),
      humanRules: _rules(json['humanRules'], 'humanRules'),
    );
  }

  Map<String, Object> toJson() => {
    'version': version,
    'normalRules': normalRules.map((rule) => rule.toJson()).toList(),
    'humanRules': humanRules.map((rule) => rule.toJson()).toList(),
  };

  GoHumanOverrideRule resolve({required int rank, required bool humanStyle}) {
    final rules = humanStyle ? humanRules : normalRules;
    final match = rules.where((rule) => rule.matches(rank)).toList();
    if (match.isEmpty) {
      throw StateError('没有覆盖 rank=$rank 的 KataGo override 规则');
    }
    // Prefer the narrowest matching range. The global fallback has no range.
    match.sort((a, b) => _rangeWidth(a).compareTo(_rangeWidth(b)));
    return match.first;
  }

  Future<String> loadConfig(GoHumanOverrideRule rule) async {
    if (rule.isGlobal) return '';
    final path = '$overridesAssetPrefix${rule.id}.cfg';
    try {
      final text = await rootBundle.loadString(path);
      GoEngineLibrary.validateOverrides(text);
      return text;
    } on FlutterError catch (error) {
      throw StateError('找不到 KataGo override 资产 $path：$error');
    }
  }

  Future<String> resolveConfig({required int rank, required bool humanStyle}) {
    return loadConfig(resolve(rank: rank, humanStyle: humanStyle));
  }

  static List<GoHumanOverrideRule> _rules(Object? value, String key) {
    if (value is! List) throw FormatException('override defaults 缺少 $key');
    final result = value
        .map((entry) {
          if (entry is! Map) throw FormatException('$key 包含无效规则');
          return GoHumanOverrideRule.fromJson(entry.cast<String, Object?>());
        })
        .toList(growable: false);
    if (result.isEmpty) throw FormatException('$key 不能为空');
    _validateOverlap(result, key);
    return result;
  }

  static void _validateOverlap(List<GoHumanOverrideRule> rules, String key) {
    final ranged = rules.where((rule) => !rule.isGlobal).toList();
    for (var i = 0; i < ranged.length; i++) {
      for (var j = i + 1; j < ranged.length; j++) {
        final a = ranged[i];
        final b = ranged[j];
        if (a.rankMax! <= b.rankMin! && b.rankMax! <= a.rankMin!) {
          throw FormatException('override 规则 $key 存在重叠范围');
        }
      }
    }
    final globals = rules.where((rule) => rule.isGlobal).length;
    if (globals > 1) throw FormatException('override 规则 $key 有多个 global');
  }

  static int _rangeWidth(GoHumanOverrideRule rule) {
    if (rule.isGlobal) return 1 << 30;
    return rule.rankMin! - rule.rankMax!;
  }
}
