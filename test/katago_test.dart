import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/katago.dart';
import 'package:easyplay/go_ai_settings.dart';
import 'package:easyplay/go_engine_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled b6 model is present and matches its pinned checksum', () async {
    final bytes = await KataGoCatalog.loadBundledB6();
    expect(bytes.length, greaterThan(3000000));
    expect(
      KataGoDownloadClient.sha256Hex(bytes),
      'f5d32604e3675c480c7c8f6aa579a1ea857135628a0afccc8fa56330fbacd38d',
    );
  });

  test('GTP wrapper sends initialization and extracts responses', () async {
    final commands = <String>[];
    final client = KataGoGtpClient((command) async {
      commands.add(command);
      if (command.startsWith('genmove')) return '= 7\nD4\n\n';
      return '=\n\n';
    });
    await client.initialize(boardSize: 13, komi: 6.5);
    expect(await client.genmove(Side.white), 'D4');
    expect(commands, ['boardsize 13', 'komi 6.5', 'clear_board', 'genmove W']);
  });

  test('KataGo config applies selected rank and play style', () {
    final source = '''
rules = tromp-taylor
maxVisits = 500
numSearchThreads = 6
# chosenMoveTemperatureEarly = 0.5
# chosenMoveTemperature = 0.1
# chosenMoveTemperatureHalflife = 19
''';
    final modern = buildKataGoConfig(
      source,
      config: const GoConfig(rules: GoRuleSet.japanese),
      settings: const GoAiSettings(
        rank: GoAiRank.dan1,
        style: GoAiStyle.modern,
      ),
    );
    expect(modern, contains('rules = japanese'));
    expect(modern, contains('maxVisits = 2500'));
    expect(modern, contains('numSearchThreads = 2'));
    expect(modern, contains('maxTime = 3'));
    expect(modern, contains('chosenMoveTemperatureEarly = 0.3'));
    expect(modern, isNot(contains('# chosenMoveTemperatureEarly')));

    final traditional = buildKataGoConfig(
      source,
      config: const GoConfig(),
      settings: const GoAiSettings(style: GoAiStyle.traditional),
      engine: const GoEngineProfile(
        id: 'quick',
        name: '快速',
        maxTimeSeconds: 1,
        searchThreads: 4,
        configOverrides: 'maxVisits = 900\nallowResignation = true',
      ),
    );
    expect(traditional, contains('chosenMoveTemperature = 0.5'));
    expect(traditional, contains('maxTime = 1'));
    expect(traditional, contains('numSearchThreads = 4'));
    expect(traditional, contains('maxVisits = 900'));
    expect(traditional, contains('allowResignation = true'));
  });
}
