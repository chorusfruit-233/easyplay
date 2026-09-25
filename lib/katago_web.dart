import 'dart:convert';
import 'dart:js_interop';

import 'game_session.dart';
import 'go_ai_settings.dart';

@JS('easyPlayKataGoGenmove')
external JSPromise<JSString> _genmove(JSString payload);
@JS('easyPlayKataGoAdjudicate')
external JSPromise<JSString> _adjudicate(JSString payload);

Future<String> genmoveOnWeb({
  required GoConfig config,
  required GoAiSettings settings,
  String? modelBase64,
  required int maxTimeSeconds,
  required int searchThreads,
  required String configOverrides,
  required List<String> setup,
  required List<String> moves,
  required Side side,
}) async {
  final payload = jsonEncode({
    'id': DateTime.now().microsecondsSinceEpoch,
    'boardSize': config.boardSize,
    'rules': switch (config.rules) {
      GoRuleSet.chinese => 'chinese',
      GoRuleSet.japanese => 'japanese',
      GoRuleSet.korean => 'korean',
    },
    'komi': config.komi,
    'maxVisits': settings.rank.maxVisits,
    'style': settings.style.name,
    'maxTimeSeconds': maxTimeSeconds,
    'searchThreads': searchThreads,
    'configOverrides': configOverrides,
    if (modelBase64 != null) 'modelBase64': modelBase64,
    'side': side == Side.black ? 'B' : 'W',
    'setup': setup,
    'moves': moves,
  });
  return (await _genmove(payload.toJS).toDart).toDart;
}

Future<Map<String, Object?>> adjudicateOnWeb({
  required GoConfig config,
  required GoAiSettings settings,
  String? modelBase64,
  required int maxTimeSeconds,
  required int searchThreads,
  required String configOverrides,
  required List<String> setup,
  required List<String> moves,
}) async {
  final payload = jsonEncode({
    'id': DateTime.now().microsecondsSinceEpoch,
    'boardSize': config.boardSize,
    'rules': switch (config.rules) {
      GoRuleSet.chinese => 'chinese',
      GoRuleSet.japanese => 'japanese',
      GoRuleSet.korean => 'korean',
    },
    'komi': config.komi,
    'maxVisits': settings.rank.maxVisits,
    'style': settings.style.name,
    'maxTimeSeconds': maxTimeSeconds,
    'searchThreads': searchThreads,
    'configOverrides': configOverrides,
    if (modelBase64 != null) 'modelBase64': modelBase64,
    'setup': setup,
    'moves': moves,
  });
  return jsonDecode((await _adjudicate(payload.toJS).toDart).toDart)
      as Map<String, Object?>;
}
