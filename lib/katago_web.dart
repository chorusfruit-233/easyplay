import 'dart:convert';
import 'dart:js_interop';

import 'game_session.dart';

@JS('easyPlayKataGoGenmove')
external JSPromise<JSString> _genmove(JSString payload);
@JS('easyPlayKataGoAdjudicate')
external JSPromise<JSString> _adjudicate(JSString payload);

Future<String> genmoveOnWeb({
  required GoConfig config,
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
    'setup': setup,
    'moves': moves,
    'side': 'W',
  });
  return (await _genmove(payload.toJS).toDart).toDart;
}

Future<Map<String, Object?>> adjudicateOnWeb({
  required GoConfig config,
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
    'setup': setup,
    'moves': moves,
  });
  return jsonDecode((await _adjudicate(payload.toJS).toDart).toDart)
      as Map<String, Object?>;
}
