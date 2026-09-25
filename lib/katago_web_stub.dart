import 'game_session.dart';
import 'go_ai_settings.dart';

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
}) => throw UnsupportedError('当前平台不是 Web');

Future<Map<String, Object?>> adjudicateOnWeb({
  required GoConfig config,
  required GoAiSettings settings,
  String? modelBase64,
  required int maxTimeSeconds,
  required int searchThreads,
  required String configOverrides,
  required List<String> setup,
  required List<String> moves,
}) => throw UnsupportedError('当前平台不是 Web');
