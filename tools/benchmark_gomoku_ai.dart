// Reproducible paired games against the frozen v1.7.0 search, at equal limits.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import '../test/gomoku/fixtures/legacy_gomoku_ai.dart';

const openings = <List<Cell>>[
  [Cell(7, 7), Cell(7, 8)],
  [Cell(7, 7), Cell(6, 8), Cell(8, 8), Cell(6, 6)],
  [Cell(7, 7), Cell(6, 7), Cell(8, 6), Cell(8, 8)],
  [Cell(7, 7), Cell(8, 8), Cell(7, 9), Cell(7, 8), Cell(6, 9), Cell(8, 9)],
  [Cell(7, 7), Cell(8, 7), Cell(6, 6), Cell(6, 8)],
  [Cell(7, 7), Cell(7, 6), Cell(8, 8), Cell(6, 7), Cell(8, 6), Cell(9, 7)],
];

Future<void> main(List<String> args) async {
  String option(String key, String fallback) {
    final i = args.indexOf('--$key');
    return i < 0 ? fallback : args[i + 1];
  }

  final pairs = int.parse(option('pairs', '3'));
  final maxNodes = int.parse(option('nodes', '256'));
  final maxDepth = int.parse(option('depth', '3'));
  final milliseconds = int.parse(option('milliseconds', '250'));
  final maxPlies = int.parse(option('plies', '225'));
  final selected = option('variant', 'all');
  final variants = GomokuVariant.values.where(
    (v) => selected == 'all' || v.name == selected,
  );
  if (pairs < 1 || variants.isEmpty) {
    throw ArgumentError('Invalid pairs or variant');
  }
  final level = GomokuAiLevel.values.byName(option('level', 'intermediate'));
  final report = await benchmarkGomokuAi(
    pairs: pairs,
    maxNodes: maxNodes,
    maxDepth: maxDepth,
    milliseconds: milliseconds,
    maxPlies: maxPlies,
    variants: variants.toList(),
    level: level,
    onProgress: stdout.writeln,
  );
  final output = option('output', '/tmp/gomoku-ai-benchmark.json');
  File(
    output,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(
    'New ${report['newWins']} / legacy ${report['legacyWins']} / draws ${report['draws']} / unfinished ${report['unfinished']}; ${report['games']} games, ${report['elapsedMs']}ms. Report: $output',
  );
}

Future<Map<String, Object?>> benchmarkGomokuAi({
  int pairs = 6,
  int maxNodes = 1000,
  int maxDepth = 3,
  int milliseconds = 5000,
  int maxPlies = 225,
  List<GomokuVariant> variants = GomokuVariant.values,
  GomokuAiLevel level = GomokuAiLevel.intermediate,
  void Function(String)? onProgress,
}) async {
  final games = <Map<String, Object?>>[];
  final clock = Stopwatch()..start();
  var newWins = 0, oldWins = 0, draws = 0, unfinished = 0;
  var newMicros = 0, oldMicros = 0, newMoves = 0, oldMoves = 0;
  var newDepth = 0, oldDepth = 0;
  for (final variant in variants) {
    // Warm both implementations before recording decision latency.
    final warmup = GomokuSession(variant: variant)..place(const Cell(7, 7));
    await GomokuAi().search(warmup, level: level, maxNodes: 64, maxDepth: 2);
    await LegacyGomokuAi().search(
      warmup,
      level: level,
      maxNodes: 64,
      maxDepth: 2,
    );
    for (var pair = 0; pair < pairs; pair++) {
      for (final newSide in Side.values) {
        final session = GomokuSession(variant: variant);
        for (final point in openings[pair % openings.length]) {
          if (!session.place(point)) throw StateError('Illegal opening');
        }
        final current = GomokuAi(random: Random(1700 + pair));
        final legacy = LegacyGomokuAi(random: Random(1700 + pair));
        while (!session.gameOver && session.moves.length < maxPlies) {
          final useNew = session.turn == newSide;
          final timer = Stopwatch()..start();
          late Cell cell;
          late int depth;
          if (useNew) {
            final result = await current.search(
              session,
              level: level,
              maxNodes: maxNodes,
              maxDepth: maxDepth,
              timeLimit: Duration(milliseconds: milliseconds),
            );
            if (result == null) throw StateError('New AI returned no move');
            cell = result.cell;
            depth = result.depth;
            newMoves++;
            newDepth += depth;
            newMicros += timer.elapsedMicroseconds;
          } else {
            final result = await legacy.search(
              session,
              level: level,
              maxNodes: maxNodes,
              maxDepth: maxDepth,
              timeLimit: Duration(milliseconds: milliseconds),
            );
            if (result == null) throw StateError('Legacy AI returned no move');
            cell = result.cell;
            depth = result.depth;
            oldMoves++;
            oldDepth += depth;
            oldMicros += timer.elapsedMicroseconds;
          }
          if (!session.place(cell)) {
            throw StateError(
              'Illegal ${useNew ? 'new' : 'old'} move at ${cell.row},${cell.col}',
            );
          }
        }
        final result = !session.gameOver
            ? 'unfinished'
            : session.winner == null
            ? 'draw'
            : session.winner == newSide
            ? 'new'
            : 'legacy';
        switch (result) {
          case 'new':
            newWins++;
          case 'legacy':
            oldWins++;
          case 'draw':
            draws++;
          default:
            unfinished++;
        }
        games.add({
          'variant': variant.name,
          'pair': pair,
          'newSide': newSide.name,
          'result': result,
          'plies': session.moves.length,
          'session': session.toJson(),
        });
        onProgress?.call(
          '${variant.name} pair $pair new ${newSide.name}: $result (${session.moves.length} plies)',
        );
      }
    }
  }
  final report = {
    'baseline': 'v1.7.0 / bc2b301',
    'level': level.name,
    'limits': {
      'nodes': maxNodes,
      'depth': maxDepth,
      'milliseconds': milliseconds,
      'maxPlies': maxPlies,
    },
    'newWins': newWins,
    'legacyWins': oldWins,
    'draws': draws,
    'unfinished': unfinished,
    'games': games.length,
    'elapsedMs': clock.elapsedMilliseconds,
    'meanNewMs': newMicros / max(1, newMoves) / 1000,
    'meanLegacyMs': oldMicros / max(1, oldMoves) / 1000,
    'meanNewDepth': newDepth / max(1, newMoves),
    'meanLegacyDepth': oldDepth / max(1, oldMoves),
    'records': games,
  };
  return report;
}
