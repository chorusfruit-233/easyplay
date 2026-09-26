import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/katago.dart';
import 'package:easyplay/go_ai_settings.dart';
import 'package:easyplay/go_engine_profiles.dart';
import 'package:easyplay/go_models.dart';
import 'package:easyplay/go_sgf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled b6 model is present and matches its pinned checksum', () async {
    final bytes = await KataGoCatalog.loadBundledB6();
    expect(bytes.length, greaterThan(3000000));
    expect(
      KataGoDownloadClient.sha256Hex(bytes),
      'f5d32604e3675c480c7c8f6aa579a1ea857135628a0afccc8fa56330fbacd38d',
    );
    expect(inspectGoModel(bytes), GoModelKind.standard);
  });

  test(
    'human config applies global and rank rules with identical final precedence',
    () {
      final config = buildKataGoConfig(
        'rules = japanese\nmaxVisits = 5\nmaxVisits = 6',
        config: const GoConfig(boardSize: 13),
        settings: const GoAiSettings(
          style: GoAiStyle.human,
          humanModelId: 'human',
          humanStyleRank: -4,
        ),
        bundledOverride: 'maxVisits=120\nnumSearchThreads=4',
        engine: const GoEngineProfile(
          id: 'test',
          name: 'test',
          customConfig: 'maxVisits=80',
          configOverrides: 'maxVisits=700\nrules=japanese\nkoRule=SIMPLE',
          humanOverrideRules: [
            GoEngineOverrideRule(
              id: 'global',
              displayName: 'all',
              configText: 'maxTime=2',
            ),
            GoEngineOverrideRule(
              id: 'range',
              displayName: '5d–6d',
              rankMin: -4,
              rankMax: -5,
              configText: 'maxVisits=300',
            ),
          ],
        ),
      );
      final values = parseKataGoConfig(config);
      expect(values['maxVisits'], '700');
      expect(values['maxTime'], '2');
      expect(values['numSearchThreads'], '4');
      expect(values['humanSLProfile'], 'rank_5d');
      expect(values['rules'], 'chinese');
      expect(values['defaultBoardSize'], '13');
      expect(values.containsKey('koRule'), false);
      expect(
        RegExp(r'^maxVisits =', multiLine: true).allMatches(config).length,
        1,
      );
    },
  );

  test(
    'switching to normal play removes human config; unlimited time clears limits',
    () {
      final values = parseKataGoConfig(
        buildKataGoConfig(
          'maxTime=2\nhumanSLProfile=rank_2d',
          config: const GoConfig(),
          settings: const GoAiSettings(),
          engine: const GoEngineProfile(
            id: 'test',
            name: 'test',
            maxTimeSeconds: 0,
          ),
        ),
      );
      expect(values['maxTime'], '1e20');
      expect(values.containsKey('humanSLProfile'), false);
    },
  );

  test('AI resignation records the correct winner and SGF result', () {
    final game = GameSession(GameType.go);
    game.placeGo(const Cell(3, 3));
    expect(game.resignGo(), true);
    expect(game.winner, Side.black);
    expect(game.calculateGoScore().result, '黑中盘胜');
    final restored = GoSgf.importGame(GoSgf.exportGame(game));
    expect(restored.goResignedSide, Side.white);
    expect(restored.resumeGo(), true);
    expect(restored.gameOver, false);
    expect(restored.moves.length, 1);
  });

  test('normal overrides follow normal rank after leaving human style', () {
    final values = parseKataGoConfig(
      buildKataGoConfig(
        '',
        config: const GoConfig(),
        settings: const GoAiSettings(rank: GoAiRank.dan1, humanStyleRank: 20),
        engine: const GoEngineProfile(
          id: 'ranked',
          name: 'Ranked',
          overrideRules: [
            GoEngineOverrideRule(
              id: 'kyu',
              displayName: 'Kyu',
              rankMin: 20,
              rankMax: 1,
              configText: 'maxVisits=25',
            ),
            GoEngineOverrideRule(
              id: 'dan',
              displayName: 'Dan',
              rankMin: 0,
              rankMax: -8,
              configText: 'maxVisits=1000',
            ),
          ],
        ),
      ),
    );
    expect(values['maxVisits'], '1000');
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
