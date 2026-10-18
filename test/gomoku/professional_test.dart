import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/ai/ai_duel_config.dart';
import 'package:easyplay/gomoku/gomoku_ai.dart';
import 'package:easyplay/gomoku/gomoku_ai_duel.dart';
import 'package:easyplay/gomoku/gomoku_rules.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OpeningAi extends GomokuAi {
  final requests = <(Side, GomokuAiLevel)>[];
  @override
  Future<GomokuAction?> decide(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
  }) {
    requests.add((source.actor, level));
    if (source.phase == GomokuPhase.exchange) {
      return Future.value(const GomokuAction.exchange(true));
    }
    return super.decide(source, level: level);
  }

  @override
  Future<GomokuAiResult?> search(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
    int? maxNodes,
    int? maxDepth,
    Duration? timeLimit,
  }) => super.search(source, level: level, maxNodes: 100, maxDepth: 1);
}

GomokuSession professionalOpening({bool exchange = false}) {
  final session = GomokuSession(variant: GomokuVariant.professional);
  for (final cell in [const Cell(7, 7), const Cell(6, 7), const Cell(6, 6)]) {
    expect(session.place(cell), isTrue);
  }
  expect(session.exchangeColors(exchange), isTrue);
  expect(session.place(const Cell(8, 8)), isTrue);
  return session;
}

GomokuSession professionalNormal({bool exchange = false}) {
  final session = professionalOpening(exchange: exchange);
  expect(session.place(const Cell(8, 7)), isTrue);
  expect(session.place(const Cell(7, 8)), isTrue);
  expect(session.place(const Cell(7, 8)), isTrue);
  return session;
}

void main() {
  test('only competitive Renju is offered for new games', () {
    expect(GomokuVariant.playable, [GomokuVariant.soosyrv8]);
    expect(GomokuSession().variant, GomokuVariant.soosyrv8);
  });

  test('one opening player places B1 W2 B3 within the 26-pattern regions', () {
    final session = GomokuSession(variant: GomokuVariant.professional);
    expect(session.actor, Side.black);
    expect(session.place(const Cell(6, 7)), isFalse);
    expect(session.moves, isEmpty);
    expect(session.place(const Cell(7, 7)), isTrue);
    expect(session.actor, Side.black);
    expect(session.turn, Side.white);
    expect(session.place(const Cell(5, 7)), isFalse);
    expect(session.place(const Cell(6, 7)), isTrue);
    expect(session.actor, Side.black);
    expect(session.place(const Cell(4, 7)), isFalse);
    expect(session.place(const Cell(5, 7)), isTrue);
    expect(session.phase, GomokuPhase.exchange);
    expect(session.actor, Side.white);
    expect(session.place(const Cell(8, 8)), isFalse);
    expect(session.pass(), isFalse);
    expect(session.moves.map((m) => m.side), [
      Side.black,
      Side.white,
      Side.black,
    ]);
  });

  test(
    'opening regions produce exactly 13 direct and 13 indirect patterns',
    () {
      for (final second in [const Cell(6, 7), const Cell(6, 6)]) {
        final session = GomokuSession(variant: GomokuVariant.professional)
          ..place(const Cell(7, 7))
          ..place(second);
        final representatives = <Cell>[];
        for (var row = 5; row <= 9; row++) {
          for (var col = 5; col <= 9; col++) {
            final cell = Cell(row, col);
            if (session.canPlace(cell) &&
                !representatives.any(
                  (other) =>
                      gomokuEquivalentProposals(session.board, cell, other),
                )) {
              representatives.add(cell);
            }
          }
        }
        expect(representatives, hasLength(13));
      }
    },
  );

  for (final exchange in [false, true]) {
    test(
      'exchange=$exchange keeps player identity through fourth and fifth moves',
      () {
        final session = professionalOpening(exchange: exchange);
        final blackPlayer = exchange ? Side.white : Side.black;
        final whitePlayer = exchange ? Side.black : Side.white;
        expect(session.exchanged, exchange);
        expect(session.actor, blackPlayer);
        expect(session.exchangeColors(!exchange), isFalse);
        expect(session.place(const Cell(8, 7)), isTrue);
        expect(session.moves, hasLength(4));
        expect(session.pieceAt(const Cell(8, 7)), isNull);
        expect(session.actor, blackPlayer);
        expect(session.place(const Cell(7, 8)), isTrue);
        expect(session.actor, whitePlayer);
        expect(session.phase, GomokuPhase.selection);
        expect(session.moves, hasLength(4));
        final before = session.toJson();
        expect(session.place(const Cell(9, 9)), isFalse);
        expect(session.toJson(), before);
        expect(session.place(const Cell(7, 8)), isTrue);
        expect(session.moves, hasLength(5));
        expect(session.pieceAt(const Cell(7, 8)), Side.black);
        expect(session.pieceAt(const Cell(8, 7)), isNull);
        expect(session.proposals, isEmpty);
        expect(session.actor, whitePlayer);
        expect(session.turn, Side.white);
        expect(session.place(const Cell(8, 7)), isTrue);
        expect(session.pieceAt(const Cell(8, 7)), Side.white);
        expect(session.actor, blackPlayer);
      },
    );
  }

  test(
    'two fifth proposals cannot be duplicate or symmetric in the four-stone board',
    () {
      final session = GomokuSession(variant: GomokuVariant.professional)
        ..place(const Cell(7, 7))
        ..place(const Cell(6, 7))
        ..place(const Cell(5, 7))
        ..exchangeColors(false)
        ..place(const Cell(9, 7));
      expect(session.place(const Cell(6, 6)), isTrue);
      final before = session.toJson();
      expect(session.place(const Cell(6, 6)), isFalse);
      expect(session.place(const Cell(6, 8)), isFalse);
      expect(session.rejectionReason(const Cell(6, 8)), contains('同形'));
      expect(session.toJson(), before);
      expect(session.place(const Cell(7, 9)), isTrue);
    },
  );

  test('an asymmetric fourth stone breaks an earlier proposal symmetry', () {
    final session = GomokuSession(variant: GomokuVariant.professional)
      ..place(const Cell(7, 7))
      ..place(const Cell(6, 7))
      ..place(const Cell(5, 7))
      ..exchangeColors(false)
      ..place(const Cell(9, 8));
    expect(session.place(const Cell(6, 6)), isTrue);
    expect(session.place(const Cell(6, 8)), isTrue);
  });

  test(
    'every opening action round-trips and undoes including exchange and proposals',
    () {
      final session = GomokuSession(variant: GomokuVariant.professional);
      final snapshots = [session.toJson()];
      const actions = [
        GomokuAction.place(Cell(7, 7)),
        GomokuAction.place(Cell(6, 7)),
        GomokuAction.place(Cell(6, 6)),
        GomokuAction.exchange(true),
        GomokuAction.place(Cell(8, 8)),
        GomokuAction.place(Cell(8, 7)),
        GomokuAction.place(Cell(7, 8)),
        GomokuAction.place(Cell(7, 8)),
        GomokuAction.pass(),
        GomokuAction.pass(),
      ];
      for (final action in actions) {
        expect(session.applyAction(action), isTrue);
        expect(
          GomokuSession.fromJson(session.toJson()).toJson(),
          session.toJson(),
        );
        expect(session.fork().toJson(), session.toJson());
        snapshots.add(session.toJson());
      }
      expect(session.gameOver, isTrue);
      expect(session.winner, isNull);
      for (var i = snapshots.length - 2; i >= 0; i--) {
        final revision = session.revision;
        expect(session.undo(), isTrue);
        final restored = GomokuSession.fromJson(snapshots[i]);
        final actual = session.toJson()..remove('revision');
        final expected = restored.toJson()..remove('revision');
        expect(actual, expected);
        expect(session.revision, greaterThan(revision));
      }
      expect(session.undo(), isFalse);
    },
  );

  test('forged action players, choices, moves and versions are rejected', () {
    final session = professionalNormal(exchange: true);
    final json = session.toJson();
    final actions = List<Map<String, Object?>>.from(json['actions'] as List);
    for (final bad in [
      {...json, 'version': 2},
      {...json, 'variant': 'freestyle'},
      {
        ...json,
        'actions': [
          ...actions.take(3),
          {...actions[3], 'player': 'black'},
          ...actions.skip(4),
        ],
      },
      {
        ...json,
        'actions': [
          ...actions.take(7),
          {...actions[7], 'row': 0, 'col': 0},
        ],
      },
      {...json, 'moves': (json['moves'] as List).take(4).toList()},
    ]) {
      expect(() => GomokuSession.fromJson(bad), throwsFormatException);
    }
  });

  test('a committed black overline loses and undo clears adjudication', () {
    final session = professionalNormal();
    const black = [
      Cell(0, 2),
      Cell(0, 3),
      Cell(0, 4),
      Cell(0, 6),
      Cell(0, 7),
      Cell(0, 5),
    ];
    const white = [
      Cell(14, 14),
      Cell(14, 12),
      Cell(14, 10),
      Cell(12, 14),
      Cell(12, 12),
      Cell(12, 10),
    ];
    for (var i = 0; i < black.length; i++) {
      expect(session.place(white[i]), isTrue);
      expect(session.place(black[i]), isTrue);
    }
    expect(session.forbiddenLoss, GomokuForbidden.overline);
    expect(session.winner, Side.white);
    expect(session.gameOver, isTrue);
    expect(
      GomokuSession.fromJson(session.toJson()).forbiddenLoss,
      GomokuForbidden.overline,
    );
    expect(session.undo(), isTrue);
    expect(session.forbiddenLoss, isNull);
    expect(session.gameOver, isFalse);
  });

  test(
    'AI completes the opening legally for both identities without mutating search input',
    () async {
      final session = GomokuSession(variant: GomokuVariant.professional);
      final ai = GomokuAi();
      for (var i = 0; i < 10; i++) {
        final before = session.toJson();
        final action = await ai.decide(session, level: GomokuAiLevel.beginner);
        expect(session.toJson(), before);
        expect(action, isNotNull);
        expect(session.applyAction(action!), isTrue);
        if (session.moves.length >= 6) break;
      }
      expect(session.phase, GomokuPhase.normal);
      expect(session.moves.length, greaterThanOrEqualTo(6));
      expect(session.proposals, isEmpty);
    },
  );

  test('cancelled opening decision cannot return an action', () async {
    final ai = GomokuAi();
    final decision = ai.decide(
      GomokuSession(variant: GomokuVariant.professional),
    );
    ai.cancel();
    expect(await decision, isNull);
  });

  testWidgets(
    'spectator step, undo and AI levels follow players across colour exchange',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ai = _OpeningAi();
      const config = AiDuelConfig(
        blackLevel: GomokuAiLevel.advanced,
        whiteLevel: GomokuAiLevel.beginner,
      );
      final duel = GomokuAiDuelController(
        session: GomokuSession(variant: GomokuVariant.professional),
        config: config,
        ai: ai,
        initiallyPaused: true,
      );
      addTearDown(duel.dispose);
      duel.start();
      for (var step = 0; step < 9; step++) {
        final player = duel.session.actor;
        duel.step();
        for (var i = 0; i < 300 && duel.thinking; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(duel.error, isNull);
        expect(duel.thinking, isFalse);
        expect(ai.requests.last, (player, config.levelFor(player)));
        expect(duel.session.actionCount, step + 1);
      }
      expect(duel.session.moves, hasLength(6));
      expect(duel.session.exchanged, isTrue);
      expect(ai.requests.take(3).map((r) => r.$1), everyElement(Side.black));
      expect(ai.requests[5].$1, Side.white);
      expect(ai.requests[6].$1, Side.white);
      expect(ai.requests[7].$1, Side.black);
      expect(ai.requests[8].$1, Side.black);
      duel.undo();
      expect(duel.session.moves, hasLength(5));
      duel.undo();
      expect(duel.session.phase, GomokuPhase.selection);
      expect(duel.session.proposals, hasLength(2));
      expect(duel.turn, Side.black);
      duel.undo();
      expect(duel.session.phase, GomokuPhase.proposals);
      expect(duel.turn, Side.white);
    },
  );
}
