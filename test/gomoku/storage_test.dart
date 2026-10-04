import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyplay/game_session.dart';
import 'package:easyplay/gomoku/gomoku_ai_level.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('保存为快照并恢复 AI 难度、执棋方、认输结果', () async {
    final session = GomokuSession()..place(const Cell(7, 7));
    session.resign(Side.white);
    final record = GomokuRecord(
      id: 'one',
      createdAt: DateTime.utc(2026, 10, 4),
      session: session,
      aiLevel: GomokuAiLevel.advanced,
      humanSide: Side.white,
    );
    session.reset();
    await GomokuStorage.save(record);
    final saved = (await GomokuStorage.list()).single;
    expect(saved.restore().pieceAt(const Cell(7, 7)), Side.black);
    expect(saved.restore().resigned, isTrue);
    expect(saved.aiLevel, GomokuAiLevel.advanced);
    expect(saved.humanSide, Side.white);
    expect(saved.createdAt, DateTime.utc(2026, 10, 4));
  });

  test('并发保存与删除按顺序执行，不丢掉其他对局', () async {
    GomokuRecord record(String id) => GomokuRecord(
      id: id,
      createdAt: DateTime.utc(2026),
      session: GomokuSession(),
    );
    await Future.wait([
      GomokuStorage.save(record('one')),
      GomokuStorage.save(record('two')),
      GomokuStorage.save(record('one')),
      GomokuStorage.delete('two'),
    ]);
    expect((await GomokuStorage.list()).map((item) => item.id), ['one']);
  });

  test('跳过损坏、未知版本和非法着法存档，保留有效记录', () async {
    final valid = GomokuRecord(
      id: 'valid',
      createdAt: DateTime.utc(2026),
      session: GomokuSession()..place(const Cell(7, 7)),
    ).toJson();
    final unknown = {...valid, 'id': 'newer', 'version': 2};
    final illegal = {
      ...valid,
      'id': 'illegal',
      'session': {
        ...(valid['session'] as Map),
        'moves': [
          {'row': -1, 'col': 7, 'side': 'black'},
        ],
      },
    };
    SharedPreferences.setMockInitialValues({
      GomokuStorage.key: jsonEncode([null, unknown, illegal, valid]),
    });
    expect((await GomokuStorage.list()).map((item) => item.id), ['valid']);
  });

  test('损坏的存储容器可恢复为空并重新保存', () async {
    SharedPreferences.setMockInitialValues({GomokuStorage.key: '{bad json'});
    expect(await GomokuStorage.list(), isEmpty);
    await GomokuStorage.save(
      GomokuRecord(
        id: 'fresh',
        createdAt: DateTime.utc(2026),
        session: GomokuSession(),
      ),
    );
    expect((await GomokuStorage.list()).single.id, 'fresh');
  });

  for (final variant in GomokuVariant.values) {
    test('${variant.label} 存档恢复规则与 AI 元数据', () async {
      final session = GomokuSession(variant: variant)..place(const Cell(7, 7));
      await GomokuStorage.save(
        GomokuRecord(
          id: variant.name,
          createdAt: DateTime.utc(2026),
          session: session,
          aiLevel: GomokuAiLevel.intermediate,
          humanSide: Side.white,
        ),
      );
      final saved = (await GomokuStorage.list()).single;
      expect(saved.variant, variant);
      expect(saved.restore().variant, variant);
      expect(saved.restore().pieceAt(const Cell(7, 7)), Side.black);
      expect(saved.aiLevel, GomokuAiLevel.intermediate);
      expect(saved.humanSide, Side.white);
    });
  }

  test('v1 历史存档迁移到自由规则，不误用新的禁手规则', () async {
    final json = GomokuRecord(
      id: 'old',
      createdAt: DateTime.utc(2026),
      session: GomokuSession()..place(const Cell(7, 7)),
    ).toJson();
    final oldState = {...json['session'] as Map, 'version': 1}
      ..remove('variant');
    SharedPreferences.setMockInitialValues({
      GomokuStorage.key: jsonEncode([
        {...json, 'session': oldState},
      ]),
    });
    final saved = (await GomokuStorage.list()).single;
    expect(saved.variant, GomokuVariant.freestyle);
    expect(saved.restore().moves.length, 1);
    await GomokuStorage.save(saved);
    expect(
      (await GomokuStorage.list()).single.restore().toJson()['version'],
      2,
    );
  });
}
