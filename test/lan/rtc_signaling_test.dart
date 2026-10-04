import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/draughts/draughts_variant.dart';
import 'package:easyplay/gomoku/gomoku_variant.dart';
import 'package:easyplay/lan/rtc_manual_signaling.dart';

void main() {
  test(
    'all configurations round-trip and answer is bound to original identity',
    () {
      for (final game in [
        'go',
        'chess',
        'gomoku',
        'gomoku-standard',
        'gomoku-renju',
        ...DraughtsVariant.values.map((v) => v.name),
      ]) {
        final variant = DraughtsVariant.values
            .where((v) => v.name == game)
            .firstOrNull;
        final offer = RtcInvitation.offer(
          variant == null
              ? (game.startsWith('gomoku') ? 'gomoku' : game)
              : 'draughts',
          'v=0\r\n',
          variant: variant,
          gomokuVariant: game == 'gomoku-standard'
              ? GomokuVariant.standard
              : game == 'gomoku-renju'
              ? GomokuVariant.renju
              : GomokuVariant.freestyle,
        );
        final restored = RtcInvitation.decode(
          offer.encode(),
          expectedType: 'offer',
        );
        expect(restored.configuration, offer.configuration);
        offer.validateAnswer(
          RtcInvitation.decode(
            restored.answer('v=0\r\n').encode(),
            expectedType: 'answer',
          ),
        );
        expect(
          () => RtcInvitation.offer(
            offer.game,
            'v=0\r\n',
            variant: variant,
            gomokuVariant: offer.gomokuVariant,
          ).validateAnswer(offer.answer('v=0\r\n')),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Gomoku answer must retain the original rule even with matching credentials',
    () {
      final offer = RtcInvitation.offer(
        'gomoku',
        'v=0\r\n',
        gomokuVariant: GomokuVariant.renju,
      );
      final wrong = RtcInvitation(
        sessionId: offer.sessionId,
        token: offer.token,
        game: 'gomoku',
        gomokuVariant: GomokuVariant.standard,
        type: 'answer',
        sdp: 'v=0\r\n',
        createdAt: offer.createdAt,
      );
      expect(() => offer.validateAnswer(wrong), throwsFormatException);
      expect(offer.answer('v=0\r\n').gomokuVariant, GomokuVariant.renju);
    },
  );
  test('reject stale, future, oversized, invalid type and unknown rules', () {
    final offer = RtcInvitation.offer('go', 'v=0\r\n');
    expect(
      () => RtcInvitation.decode(
        offer.encode(),
        now: DateTime.now().add(const Duration(minutes: 31)),
      ),
      throwsFormatException,
    );
    expect(
      () => RtcInvitation.decode(
        offer.encode(),
        now: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
      throwsFormatException,
    );
    expect(
      () => RtcInvitation.decode('x' * (RtcInvitation.maxBytes + 1)),
      throwsFormatException,
    );
    expect(
      () => RtcInvitation.decode(offer.encode(), expectedType: 'answer'),
      throwsFormatException,
    );
    final data = jsonDecode(offer.encode()) as Map<String, dynamic>;
    for (final invalid in [
      {'formatVersion': 2},
      {'formatVersion': 1.0},
      {'sessionId': 'guessable'},
      {
        'description': {'type': 'offer', 'sdp': 7},
      },
      {'game': 'draughts', 'variant': 'unknown', 'rulesVersion': 1},
      {'game': 'gomoku', 'boardSize': 15, 'rulesVersion': 2},
      {
        'game': 'gomoku',
        'boardSize': 15,
        'rulesVersion': 1,
        'variant': 'freestyle',
      },
      {
        'game': 'gomoku',
        'boardSize': 15,
        'rulesVersion': 2,
        'variant': 'unknown',
      },
      {'game': 'gomoku', 'boardSize': 19, 'rulesVersion': 1},
      {'game': 'unknown'},
    ]) {
      expect(
        () => RtcInvitation.decode(jsonEncode({...data, ...invalid})),
        throwsFormatException,
      );
    }
  });
}
