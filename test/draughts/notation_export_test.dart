import 'dart:math';

import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/game_session.dart' show Cell, Side;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export file names bound and sanitize external record identifiers', () {
    final record = DraughtsRecord.fromSession(
      DraughtsSession(DraughtsRules.forVariant(DraughtsVariant.english)),
      id: '../${'record' * 40}',
      createdAt: DateTime.utc(2026, 10, 18),
    );
    final fileName = DraughtsNotation.fileName(record);
    expect(fileName, startsWith('checkers_english_20261018T000000000Z_'));
    expect(fileName, endsWith('.pdn'));
    expect(fileName, isNot(contains('/')));
    expect(fileName.length, lessThan(100));
  });

  const descriptors = {
    DraughtsVariant.english: '21,B,8,8,N1,0',
    DraughtsVariant.international: '20,W,10,10,N2,0',
    DraughtsVariant.brazilian: '26,W,8,8,N2,0',
    DraughtsVariant.russian: '25,W,8,8,N2,0',
    DraughtsVariant.pool: '23,W,8,8,N2,0',
    DraughtsVariant.italian: '22,W,8,8,N2,0',
    DraughtsVariant.spanish: '24,W,8,8,N2,0',
    DraughtsVariant.turkish: '30,W,8,8,A0,0',
  };

  for (final variant in DraughtsVariant.values) {
    for (final winner in [Side.black, Side.white, null]) {
      test('${variant.name} PDN result preserves ${winner?.name ?? 'draw'}', () {
        final session = DraughtsSession(DraughtsRules.forVariant(variant));
        session.applyMove(session.legalMoves().first);
        session.applyMove(session.legalMoves().first);
        if (winner == null) {
          session.agreeDraw();
        } else {
          session.resign(winner == Side.black ? Side.white : Side.black);
        }
        final record = DraughtsRecord.fromSession(session);
        final pdn = DraughtsNotation.exportPdn(record);
        final firstWins = winner == session.rules.firstMove;
        final international = variant == DraughtsVariant.international;
        final expected = winner == null
            ? (international ? '1-1' : '1/2-1/2')
            : firstWins
            ? (international ? '2-0' : '1-0')
            : (international ? '0-2' : '0-1');
        expect(pdn, contains('[GameType "${descriptors[variant]}"]'));
        expect(pdn, contains('[EasyPlayNotationVersion "2"]'));
        expect(pdn, contains('[Result "$expected"]'));
        expect(pdn, endsWith(expected));
        final imported = DraughtsNotation.importPdn(pdn);
        expect(imported.result, record.result);
        expect(imported.restore().result?.winner, winner);
        expect(imported.restore().gameOver, isTrue);

        // Version 1 exports had no GameType/version tag and always encoded the
        // internal black-first score, including for the white-first variants.
        final legacy = pdn
            .replaceAll(RegExp(r'^\[GameType[^\n]*\n', multiLine: true), '')
            .replaceAll(
              RegExp(r'^\[EasyPlayNotationVersion[^\n]*\n', multiLine: true),
              '',
            )
            .replaceFirst(
              '[Result "$expected"]',
              '[Result "${record.result}"]',
            );
        final legacyBody =
            legacy.substring(0, legacy.length - expected.length) +
            record.result!;
        final old = DraughtsNotation.importPdn(legacyBody);
        expect(old.result, record.result);
        expect(old.restore().result?.winner, winner);
        final reexported = DraughtsNotation.exportPdn(old);
        expect(reexported, contains('[Result "$expected"]'));
      });
    }
  }

  test('GameType-only International PDN3 imports its first-player score', () {
    final imported = DraughtsNotation.importPdn(
      '[GameType "20"]\n[Result "2-0"]\n\n1. 31-26 2-0',
    );
    expect(imported.variant, DraughtsVariant.international);
    expect(imported.result, '0-1');
    expect(imported.restore().result?.winner, Side.white);
  });

  test(
    'explicit Brazilian and Spanish descriptors retain app square numbering',
    () {
      for (final descriptor in ['26,W,8,8,N2,0', '24,W,8,8,N2,0']) {
        final source = '[GameType "$descriptor"]\n[Result "*"]\n\n1. 21-17 *';
        final imported = DraughtsNotation.importPdn(source);
        expect(imported.moves.single.path, [
          const Cell(5, 0),
          const Cell(4, 1),
        ]);
        expect(imported.restore().pieceAt(const Cell(4, 1))?.side, Side.white);
        final abbreviated = source.replaceFirst(
          descriptor,
          descriptor.split(',').first,
        );
        expect(
          () => DraughtsNotation.importPdn(abbreviated),
          throwsFormatException,
        );
      }
    },
  );

  test('conflicting PDN result tag and movetext are rejected', () {
    expect(
      () =>
          DraughtsNotation.importPdn('[GameType "21"]\n[Result "1-0"]\n\n0-1'),
      throwsFormatException,
    );
  });

  test('GameType must agree with the variant and supported board settings', () {
    for (final source in [
      '[Variant "English"]\n[GameType "20"]\n\n*',
      '[GameType "23"]\n\n*', // Default Pool starts black; app starts white.
      '[GameType "22"]\n\n*', // Default Italian inverts the playable squares.
      '[GameType "24"]\n\n*', // Default Spanish uses N1/inverted squares.
      '[GameType "26"]\n\n*', // Default Brazilian uses algebraic notation.
      '[GameType "20,W,8,8,N2,0"]\n\n*',
    ]) {
      expect(() => DraughtsNotation.importPdn(source), throwsFormatException);
    }
  });

  for (final variant in DraughtsVariant.values) {
    test('${variant.name} PDN retains legal full paths, date and result', () {
      final session = DraughtsSession(DraughtsRules.forVariant(variant));
      final random = Random(8);
      for (var i = 0; i < 80 && !session.gameOver; i++) {
        final moves = session.legalMoves();
        session.applyMove(moves[random.nextInt(moves.length)]);
      }
      expect(session.moves.any((move) => move.path.length > 2), isTrue);
      if (!session.gameOver) session.resign(Side.white);
      final record = DraughtsRecord.fromSession(
        session,
        id: 'export-${variant.name}',
        createdAt: DateTime.utc(2026, 10, 18),
      );
      final pdn = DraughtsNotation.exportPdn(record);
      if (variant == DraughtsVariant.russian) {
        expect(pdn, contains(':'));
      }
      final imported = DraughtsNotation.importPdn(pdn);
      expect(imported.variant, variant);
      expect(imported.moves, record.moves);
      expect(imported.result, record.result);
      expect(imported.createdAt, DateTime(2026, 10, 18));
      final restored = imported.restore();
      expect(restored.moves, record.moves);
      expect(
        restored.position.signature(restored.turn),
        session.position.signature(session.turn),
      );
      expect(restored.result?.winner, session.result?.winner);
      expect(DraughtsNotation.fileName(record), endsWith('.pdn'));
    });
  }
}
