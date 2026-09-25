import 'game_session.dart';

Future<String> genmoveOnWeb({
  required GoConfig config,
  required List<String> setup,
  required List<String> moves,
}) => throw UnsupportedError('当前平台不是 Web');

Future<Map<String, Object?>> adjudicateOnWeb({
  required GoConfig config,
  required List<String> setup,
  required List<String> moves,
}) => throw UnsupportedError('当前平台不是 Web');
