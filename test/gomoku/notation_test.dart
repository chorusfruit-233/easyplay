import 'dart:convert';

import 'package:easyplay/ai/ai_duel_config.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_sgf.dart';
import 'package:easyplay/gomoku/gomoku_ai_level.dart';
import 'package:easyplay/gomoku/gomoku_notation.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:flutter_test/flutter_test.dart';

GomokuSession _proposals() => GomokuSession()
  ..place(const Cell(7, 7))
  ..place(const Cell(6, 7))
  ..place(const Cell(5, 7))
  ..exchangeColors(true)
  ..place(const Cell(9, 7))
  ..declareProposals(2)
  ..exchangeColors(false)
  ..place(const Cell(4, 4))
  ..place(const Cell(4, 5));

GomokuRecord _record(GomokuSession session) => GomokuRecord(
  id: 'test/[file]\\name',
  createdAt: DateTime.utc(2026, 10, 18, 3, 4, 5),
  session: session,
  aiDuel: const AiDuelConfig(
    blackLevel: GomokuAiLevel.advanced,
    whiteLevel: GomokuAiLevel.beginner,
  ),
);

void main() {
  test('SGF exports GM4, final player colors, selected fifth and passes', () {
    final session = _proposals()
      ..place(const Cell(4, 5))
      ..pass()
      ..place(const Cell(10, 10))
      ..pass()
      ..pass();
    expect(session.gameOver, isTrue);
    final record = _record(session);
    final before = record.toJson();
    final sgf = GomokuNotation.toSgf(record);
    final root = GoSgf.parseRecord(sgf).root;
    expect(root.properties['GM'], ['4']);
    expect(root.properties['RU'], ['Soosyrv-8']);
    expect(root.properties['SZ'], ['15']);
    expect(root.properties['DT'], ['2026-10-18']);
    expect(root.properties['PB'], ['AI 初级']);
    expect(root.properties['PW'], ['AI 高级']);
    expect(root.properties['RE'], ['0']);
    final moves = <Map<String, List<String>>>[];
    for (var node = root.mainChild; node != null; node = node.mainChild) {
      moves.add(node.properties);
    }
    expect(moves, [
      {
        'B': ['hh'],
      },
      {
        'W': ['hg'],
      },
      {
        'B': ['hf'],
      },
      {
        'W': ['hj'],
      },
      {
        'B': ['fe'],
      },
      {
        'W': [''],
      },
      {
        'B': ['kk'],
      },
      {
        'W': [''],
      },
      {
        'B': [''],
      },
    ]);
    expect(sgf, isNot(contains(';B[ee]')));
    expect(record.toJson(), before);
  });

  test('pending proposals remain in JSON without appearing as SGF stones', () {
    final record = _record(_proposals());
    final decoded = jsonDecode(GomokuNotation.toJson(record));
    final restored = GomokuRecord.fromJson(decoded);
    expect(restored.toJson(), record.toJson());
    expect(restored.restore().proposals, [const Cell(4, 4), const Cell(4, 5)]);
    expect(restored.restore().phase, GomokuPhase.selection);
    expect(restored.restore().exchanged, isTrue);
    expect(restored.aiDuel!.blackLevel, GomokuAiLevel.advanced);
    expect(restored.aiDuel!.whiteLevel, GomokuAiLevel.beginner);
    final sgf = GomokuNotation.toSgf(record);
    expect(sgf, contains(';B[hh];W[hg];B[hf];W[hj])'));
    expect(sgf, isNot(contains('RE[')));
    expect(sgf, contains('JSON 完整备份'));
  });

  test(
    'JSON retains swaps, declared count, selected proposals, pass and resign',
    () {
      final session = _proposals()
        ..place(const Cell(4, 5))
        ..pass()
        ..resign(Side.black);
      final record = GomokuRecord(
        id: 'human-white',
        createdAt: DateTime.utc(2026),
        session: session,
        humanSide: Side.white,
        aiLevel: GomokuAiLevel.advanced,
      );
      final restored = GomokuRecord.fromJson(
        jsonDecode(GomokuNotation.toJson(record)),
      );
      expect(restored.toJson(), record.toJson());
      final actions = (restored.toJson()['session'] as Map)['actions'] as List;
      expect(actions.where((a) => a['type'] == 'exchange'), hasLength(2));
      expect(actions.singleWhere((a) => a['type'] == 'declare')['count'], 2);
      expect(actions.last['type'], 'pass');
      expect(restored.restore().resigned, isTrue);
      final root = GoSgf.parseRecord(GomokuNotation.toSgf(record)).root;
      expect(root.properties['RE'], ['W+R']);
      expect(root.properties['PB'], ['玩家']);
      expect(root.properties['PW'], ['AI 高级']);
    },
  );

  for (final variant in GomokuVariant.values) {
    test(
      '${variant.name}: export preserves rules and supports old records',
      () {
        final session = GomokuSession(variant: variant)
          ..place(const Cell(7, 7));
        final record = _record(session);
        final root = GoSgf.parseRecord(GomokuNotation.toSgf(record)).root;
        expect(root.properties['RU']!.single, isNotEmpty);
        expect(root.mainChild!.properties, {
          'B': ['hh'],
        });
        expect(
          GomokuRecord.fromJson(
            jsonDecode(GomokuNotation.toJson(record)),
          ).variant,
          variant,
        );
      },
    );
  }

  test(
    'export filenames include date, unique record id and safe extension',
    () {
      final fileName = GomokuNotation.fileName(_record(GomokuSession()), 'sgf');
      expect(fileName, startsWith('gomoku_20261018T030405000Z_'));
      expect(fileName, endsWith('.sgf'));
      expect(fileName, isNot(contains(RegExp(r'[/\\\[\]:]'))));
    },
  );
}
