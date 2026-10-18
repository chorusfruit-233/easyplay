import 'dart:convert';

import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:flutter_test/flutter_test.dart';

GomokuSession fourStones({bool swap = false}) => GomokuSession()
  ..place(const Cell(7, 7))
  ..place(const Cell(6, 7))
  ..place(const Cell(5, 7))
  ..exchangeColors(swap)
  ..place(const Cell(9, 7));

void main() {
  test('new games offer only Soosõrv-8; v3 five-hand-two stays v3', () {
    expect(GomokuVariant.playable, [GomokuVariant.soosyrv8]);
    expect(GomokuSession().toJson()['version'], 4);
    final legacy = GomokuSession(variant: GomokuVariant.professional)
      ..place(const Cell(7, 7));
    expect(legacy.toJson()['version'], 3);
    expect(GomokuSession.fromJson(legacy.toJson()).toJson(), legacy.toJson());
    expect(legacy.variant.playableRule, isFalse);
  });

  for (final first in [false, true]) {
    for (final second in [false, true]) {
      for (var count = 1; count <= 8; count++) {
        test(
          'swap=$first/$second, N=$count: actors, proposals, replay, undo',
          () {
            final session = fourStones(swap: first);
            final snapshots = [session.toJson()];
            void apply(GomokuAction action) {
              expect(session.applyAction(action), isTrue);
              expect(
                GomokuSession.fromJson(session.toJson()).toJson(),
                session.toJson(),
              );
              expect(session.fork().toJson(), session.toJson());
              snapshots.add(session.toJson());
            }

            expect(session.phase, GomokuPhase.declaration);
            expect(session.actor, first ? Side.black : Side.white);
            expect(session.acceptsPlacement, isFalse);
            expect(session.pass(), isFalse);
            expect(session.exchangeColors(false), isFalse);
            apply(GomokuAction.declare(count));
            expect(session.actor, first ? Side.white : Side.black);
            expect(session.phase, GomokuPhase.secondExchange);
            expect(session.declareProposals(count), isFalse);
            apply(GomokuAction.exchange(second));
            final exchanged = first != second;
            final black = exchanged ? Side.white : Side.black;
            final white = exchanged ? Side.black : Side.white;
            expect(session.actor, black);
            expect(session.exchanged, exchanged);
            expect(session.proposalCount, count);
            for (var i = 0; i < count; i++) {
              Cell? next;
              for (var row = 4; row <= 10 && next == null; row++) {
                for (var col = 4; col <= 10; col++) {
                  if (session.canPlace(Cell(row, col))) {
                    next = Cell(row, col);
                    break;
                  }
                }
              }
              expect(next, isNotNull);
              apply(GomokuAction.place(next!));
              expect(session.moves, hasLength(4));
              expect(session.pieceAt(next), isNull);
            }
            expect(session.phase, GomokuPhase.selection);
            expect(session.actor, white);
            final proposals = session.proposals;
            final chosen = proposals.last;
            apply(GomokuAction.place(chosen));
            expect(session.moves.last.side, Side.black);
            expect(session.actor, white);
            expect(session.turn, Side.white);
            expect(session.phase, GomokuPhase.normal);
            for (final other in proposals.where((p) => p != chosen)) {
              expect(session.pieceAt(other), isNull);
            }
            apply(const GomokuAction.pass());
            apply(const GomokuAction.pass());
            expect(session.gameOver, isTrue);
            for (var i = snapshots.length - 2; i >= 0; i--) {
              expect(session.undo(), isTrue);
              expect(
                session.toJson()..remove('revision'),
                Map.of(snapshots[i])..remove('revision'),
              );
            }
            expect(session.phase, GomokuPhase.declaration);
            expect(session.declaredProposals, isNull);
          },
        );
      }
    }
  }

  test(
    'declaration 1–8 only, board blocked until both decisions are recorded',
    () {
      final session = fourStones();
      final before = session.toJson();
      for (final count in [-1, 0, 9, 100]) {
        expect(session.declareProposals(count), isFalse);
        expect(session.toJson(), before);
      }
      expect(session.place(const Cell(8, 8)), isFalse);
      expect(session.declareProposals(8), isTrue);
      expect(session.place(const Cell(8, 8)), isFalse);
      expect(session.exchangeColors(false), isTrue);
    },
  );

  test(
    'every prior proposal and its board-preserving symmetry is excluded',
    () {
      final session = fourStones()
        ..declareProposals(8)
        ..exchangeColors(false);
      for (final point in [
        const Cell(6, 6),
        const Cell(7, 5),
        const Cell(9, 4),
      ]) {
        expect(session.place(point), isTrue);
      }
      final before = session.toJson();
      for (final point in [
        const Cell(6, 6),
        const Cell(6, 8),
        const Cell(7, 9),
        const Cell(9, 10),
      ]) {
        expect(session.place(point), isFalse);
        expect(session.toJson(), before);
      }
    },
  );

  test(
    'tampered N, second-swap actor/order and profile/version are rejected',
    () {
      final session = fourStones(swap: true)
        ..declareProposals(3)
        ..exchangeColors(true);
      Map<String, dynamic> copy() =>
          jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>;
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['version'] = 3,
        (j) => j['variant'] = 'professional',
        (j) => j['actions'][5]['count'] = 9,
        (j) => j['actions'][5]['player'] = 'white',
        (j) => j['actions'][6]['player'] = 'black',
        (j) => (j['actions'] as List).removeAt(5),
      ]) {
        final json = copy();
        mutate(json);
        expect(() => GomokuSession.fromJson(json), throwsFormatException);
      }
      session.reset();
      expect(session.declaredProposals, isNull);
      expect(session.exchanged, isFalse);
      expect(session.phase, GomokuPhase.opening);
    },
  );
}
