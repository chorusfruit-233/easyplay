import 'dart:async';

import 'package:easyplay/game_session.dart' show Cell;
import 'package:easyplay/gomoku/engine/rapfi_player.dart';
import 'package:easyplay/gomoku/engine/rapfi_transport.dart';
import 'package:easyplay/gomoku/gomoku_ai_level.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'soosyrv8_test.dart' show fourStones;

class FakeRapfi implements RapfiTransport {
  final output = StreamController<String>.broadcast(sync: true);
  final commands = <String>[];
  void Function(FakeRapfi, int)? search;
  bool closed = false;
  @override
  Stream<String> get lines => output.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> send(String command) async {
    commands.add(command);
    if (command.startsWith('START')) output.add('OK');
    if (command.startsWith('YXBALANCEONE')) {
      search?.call(this, 1);
    }
    if (command.startsWith('YXNBEST')) {
      search?.call(this, int.parse(command.split(' ').last));
    }
  }

  void candidates(List<(Cell, int)> candidates, {int depth = 2}) {
    for (var i = 0; i < candidates.length; i++) {
      final (cell, score) = candidates[i];
      output.add(
        'MESSAGE depth $depth-3${candidates.length > 1 ? ' multipv ${i + 1}' : ''} ev $score n 100 tm 1 pv ${String.fromCharCode(65 + cell.col)}${cell.row + 1}',
      );
    }
  }

  void best(Cell cell) => output.add('${cell.col},${cell.row}');
}

void main() {
  test(
    'N uses the white-selected Nth score and ignores partial next MultiPV',
    () async {
      final transport = FakeRapfi();
      transport.search = (t, count) {
        expect(count, 8);
        t.candidates([
          for (var i = 0; i < 8; i++)
            (Cell(4, i), [500, 200, -10, -200, -300, -400, -500, -600][i]),
        ]);
        // This interrupted deeper iteration must not replace the completed set.
        t.candidates([(const Cell(4, 0), -9000)], depth: 3);
        t.best(const Cell(4, 0));
      };
      final ai = RapfiPlayer(transportFactory: () => transport);
      addTearDown(ai.dispose);
      final source = fourStones();
      final before = source.toJson();
      final declaration = await ai.decide(source);
      expect(declaration?.type, GomokuActionType.declare);
      expect(declaration?.count, 3);
      expect(source.toJson(), before);
      source.declareProposals(3);
      final exchange = await ai.decide(source);
      expect(exchange?.exchange, isTrue); // Third candidate favours white.
      expect(transport.commands, contains('INFO RULE 4'));
      expect(transport.commands, contains('INFO STRENGTH 100'));
    },
  );

  test(
    'W4 uses balance search because black can take white in the second swap',
    () async {
      final t = FakeRapfi()
        ..search = (t, _) {
          t.candidates([(const Cell(8, 8), 0)]);
          t.best(const Cell(8, 8));
        };
      final ai = RapfiPlayer(transportFactory: () => t);
      addTearDown(ai.dispose);
      final session = GomokuSession()
        ..place(const Cell(7, 7))
        ..place(const Cell(6, 7))
        ..place(const Cell(6, 6))
        ..exchangeColors(false);
      final action = await ai.decide(session, level: GomokuAiLevel.beginner);
      expect(action?.cell, const Cell(8, 8));
      expect(t.commands, contains('YXBALANCEONE 0'));
      expect(t.commands, isNot(contains('YXNBEST 1')));
      expect(t.commands, contains('INFO STRENGTH 100'));
      expect(t.commands, contains('INFO TIMEOUT_TURN 500'));
      expect(session.moves, hasLength(3));
    },
  );

  test(
    'proposals block all earlier points and equivalent reflections',
    () async {
      final t = FakeRapfi()
        ..search = (t, count) {
          t.candidates([(const Cell(4, 4), 100)]);
          t.best(const Cell(4, 4));
        };
      final ai = RapfiPlayer(transportFactory: () => t);
      addTearDown(ai.dispose);
      final session = fourStones()
        ..declareProposals(8)
        ..exchangeColors(false)
        ..place(const Cell(6, 6))
        ..place(const Cell(7, 5));
      final action = await ai.decide(session);
      expect(action?.cell, const Cell(4, 4));
      final block = t.commands.singleWhere((c) => c.startsWith('YXBLOCK\n'));
      for (final coordinates in ['6,6', '8,6', '5,7', '9,7']) {
        expect(block.split('\n'), contains(coordinates));
      }
    },
  );

  test(
    'white selects the best resulting W6 position among actual proposals',
    () async {
      final t = FakeRapfi();
      var calls = 0;
      t.search = (t, count) {
        final score = ++calls == 1 ? -100 : 200;
        t.candidates([(const Cell(10, 10), score)]);
        t.best(const Cell(10, 10));
      };
      final ai = RapfiPlayer(transportFactory: () => t);
      addTearDown(ai.dispose);
      final session = fourStones()
        ..declareProposals(2)
        ..exchangeColors(true)
        ..place(const Cell(6, 6))
        ..place(const Cell(7, 5));
      final action = await ai.decide(session);
      expect(action?.cell, const Cell(7, 5));
      expect(session.moves, hasLength(4));
      final boards = t.commands.where((s) => s.startsWith('YXBOARD')).toList();
      expect(boards[0], contains('6,6,2'));
      expect(boards[1], contains('5,7,2'));
    },
  );

  test(
    'illegal output and startup errors surface, without local AI fallback',
    () async {
      final t = FakeRapfi()..search = (t, _) => t.best(const Cell(7, 7));
      final ai = RapfiPlayer(transportFactory: () => t);
      addTearDown(ai.dispose);
      final session = GomokuSession(variant: GomokuVariant.renju)
        ..place(const Cell(7, 7));
      expect(await ai.decide(session), isNull);
      expect(ai.failureReason, contains('非法落点'));
      expect(session.moves, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      expect(t.closed, isTrue);
    },
  );

  test(
    'cancel destroys the busy engine, rejects late output and recreates it',
    () async {
      final old = FakeRapfi(),
          fresh = FakeRapfi()
            ..search = (t, _) {
              t.candidates([(const Cell(6, 7), 1)]);
              t.best(const Cell(6, 7));
            };
      final transports = [old, fresh];
      final ai = RapfiPlayer(transportFactory: () => transports.removeAt(0));
      addTearDown(ai.dispose);
      final session = GomokuSession(variant: GomokuVariant.renju)
        ..place(const Cell(7, 7));
      final pending = ai.decide(session);
      while (!old.commands.any((s) => s.startsWith('YXNBEST'))) {
        await Future<void>.delayed(Duration.zero);
      }
      ai.cancel();
      expect(await pending, isNull);
      old.best(const Cell(0, 0));
      final result = await ai.decide(session, level: GomokuAiLevel.beginner);
      expect(old.closed, isTrue);
      expect(result?.cell, const Cell(6, 7));
      expect(fresh.commands, contains('INFO STRENGTH 10'));
      expect(ai.failureReason, isNull);
    },
  );

  test(
    'BOARD preserves chronological colours and a trailing pass after swaps',
    () {
      final session = fourStones(swap: true)
        ..declareProposals(1)
        ..exchangeColors(true)
        ..place(const Cell(6, 6))
        ..place(const Cell(6, 6))
        ..pass();
      final command = RapfiPlayer.positionCommand(session);
      expect(command, startsWith('YXBOARD\n7,7,1\n7,6,2\n7,5,1\n'));
      expect(command, endsWith('6,6,1\n-1,-1,2\nDONE'));
    },
  );
}
