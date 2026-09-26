import 'package:flutter/services.dart';

import 'game_session.dart';
import 'go_ai_settings.dart';
import 'go_engine_profiles.dart';
import 'go_human_profiles.dart';

Map<String, String> parseKataGoConfig(String source) {
  GoEngineLibrary.validateOverrides(source);
  final values = <String, String>{};
  for (final line in source.split('\n')) {
    final text = line.split('#').first.trim();
    if (text.isEmpty) continue;
    final at = text.indexOf('=');
    values[text.substring(0, at).trim()] = text.substring(at + 1).trim();
  }
  return values;
}

Future<String> resolveKataGoConfig({
  required GoConfig config,
  required GoAiSettings settings,
  GoEngineProfile engine = GoEngineProfile.builtIn,
  bool forWeb = false,
}) async {
  final source = await rootBundle.loadString('assets/katago/android_gtp.cfg');
  final catalog = await GoHumanOverrideCatalog.load();
  final bundled = await catalog.resolveConfig(
    rank: settings.resolvedHumanStyleRank,
    humanStyle: settings.usesHumanStyle,
  );
  return buildKataGoConfig(
    source,
    config: config,
    settings: settings,
    engine: engine,
    bundledOverride: bundled,
    forWeb: forWeb,
  );
}

/// Both Android and static Web execute this exact configuration.
/// Precedence: defaults, search controls, bundled rank rules, custom cfg,
/// custom global/rank rules, free-form overrides, then board/runtime identity.
String buildKataGoConfig(
  String source, {
  required GoConfig config,
  required GoAiSettings settings,
  GoEngineProfile engine = GoEngineProfile.builtIn,
  String bundledOverride = '',
  bool forWeb = false,
}) {
  config.validate();
  settings.validateHumanStyle();
  final values = parseKataGoConfig(source);
  values.addAll({
    'maxVisits': '${settings.rank.maxVisits}',
    'numSearchThreads': '${engine.searchThreads}',
    'maxTime': engine.maxTimeSeconds == 0 ? '1e20' : '${engine.maxTimeSeconds}',
    'logAllGTPCommunication': 'false',
    'logSearchInfo': 'false',
    'logSearchInfoForChosenMove': 'false',
    'logToStderr': 'true',
    'allowResignation': 'false',
    'ponderingEnabled': 'false',
    'chosenMoveTemperatureEarly': settings.style == GoAiStyle.traditional
        ? '0.7'
        : '0.3',
    'chosenMoveTemperature': settings.style == GoAiStyle.traditional
        ? '0.5'
        : '0.1',
    'chosenMoveTemperatureHalflife': settings.style == GoAiStyle.traditional
        ? '19'
        : '30',
  });
  values.addAll(parseKataGoConfig(bundledOverride));
  values.addAll(parseKataGoConfig(engine.customConfig));
  final rules = settings.usesHumanStyle
      ? engine.humanOverrideRules
      : engine.overrideRules;
  GoEngineOverrideRule.validateList(rules);
  final overrideRank = settings.usesHumanStyle
      ? settings.resolvedHumanStyleRank
      : settings.rank.humanRank;
  for (final rule in [
    ...rules.where((r) => r.isGlobal),
    ...rules.where((r) => !r.isGlobal && r.matches(overrideRank)),
  ]) {
    values.addAll(parseKataGoConfig(rule.configText));
  }
  values.addAll(parseKataGoConfig(engine.configOverrides));
  // The selected game's rules and board size cannot be changed by old cfgs.
  for (final key in [
    'koRule',
    'scoringRule',
    'taxRule',
    'multiStoneSuicideLegal',
    'hasButton',
    'whiteHandicapBonus',
    'friendlyPassOk',
    'fpok',
    'logDir',
    'logFile',
  ]) {
    values.remove(key);
  }
  values['rules'] = config.rules.name;
  values['defaultBoardSize'] = '${config.boardSize}';
  values['komi'] = '${config.komi}';
  if (settings.usesHumanStyle) {
    values['humanSLProfile'] = settings.resolvedHumanSLProfile;
  } else {
    values.removeWhere((key, _) => key.startsWith('humanSL'));
  }
  if (engine.backend == GoEngineBackend.opencl && !forWeb) {
    values['openclDeviceToUse'] = '${engine.openclGpuIdx ?? 0}';
  } else {
    values.removeWhere((key, _) => key.startsWith('opencl'));
  }
  return '${values.entries.map((e) => '${e.key} = ${e.value}').join('\n')}\n';
}
