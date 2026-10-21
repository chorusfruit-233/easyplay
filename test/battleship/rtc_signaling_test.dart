import 'dart:convert';

import 'package:easyplay/battleship/battleship.dart';
import 'package:easyplay/battleship/multiplayer/battleship_replica.dart';
import 'package:easyplay/battleship/multiplayer/battleship_room_coordinator.dart';
import 'package:easyplay/battleship/multiplayer/battleship_rtc_room.dart';
import 'package:easyplay/lan/message_transport.dart';
import 'package:easyplay/lan/rtc_transport.dart';
import 'package:flutter_test/flutter_test.dart';

BattleshipRtcInvitation invitation({DateTime? createdAt}) =>
    BattleshipRtcInvitation(
      roomId: battleshipSecret(),
      sessionId: battleshipSecret(),
      token: battleshipSecret(),
      sdp: 'v=0\r\na=candidate:example\r\n',
      type: 'offer',
      createdAt: createdAt,
    );

Map<String, Object?> fields(BattleshipRtcInvitation value) =>
    Map<String, Object?>.from(jsonDecode(value.encode()) as Map);

void main() {
  test('typed signaling round-trips only channel identities and SDP', () {
    final offer = invitation();
    final wire = fields(offer);
    expect(wire['game'], 'battleship');
    expect(wire['seat'], BattleshipSeat.player2.index);
    expect(
      wire.keys,
      unorderedEquals([
        'game',
        'formatVersion',
        'protocolVersion',
        'rulesVersion',
        'roomId',
        'seat',
        'sessionId',
        'token',
        'sdp',
        'type',
        'createdAt',
      ]),
    );
    final restored = BattleshipRtcInvitation.decode(
      offer.encode(),
      type: 'offer',
    );
    expect(restored.roomId, offer.roomId);
    expect(restored.sessionId, offer.sessionId);
    expect(restored.token, offer.token);
    expect(restored.sdp, offer.sdp);
    final answer = BattleshipRtcInvitation.decode(
      restored.answer('v=0\r\na=answer\r\n').encode(),
      type: 'answer',
    );
    expect(answer.createdAt, offer.createdAt);
    expect(() => offer.validateAnswer(answer), returnsNormally);
    expect(answer.sdp, contains('a=answer'));
  });

  test(
    'rejects wrong game, noninteger versions, host seat and invalid SDP',
    () {
      final original = fields(invitation());
      for (final patch in <Map<String, Object?>>[
        {'game': 'doudizhu'},
        {'game': 'unknown'},
        {'formatVersion': 2},
        {'formatVersion': 1.0},
        {'protocolVersion': 2},
        {'protocolVersion': 1.0},
        {'rulesVersion': 2},
        {'rulesVersion': 1.0},
        {'seat': 0},
        {'seat': 1.0},
        {'seat': 2},
        {'sdp': 7},
        {'sdp': 'not SDP'},
        {'type': 'answer'},
      ]) {
        expect(
          () => BattleshipRtcInvitation.decode(
            jsonEncode({...original, ...patch}),
            type: 'offer',
          ),
          throwsFormatException,
          reason: '$patch',
        );
      }
      expect(
        () =>
            BattleshipRtcInvitation.decode(jsonEncode(original), type: 'bogus'),
        throwsFormatException,
      );
    },
  );

  test(
    'requires every identity field and rejects private or unknown fields',
    () {
      final original = fields(invitation());
      for (final field in original.keys) {
        final missing = {...original}..remove(field);
        expect(
          () => BattleshipRtcInvitation.decode(
            jsonEncode(missing),
            type: 'offer',
          ),
          throwsFormatException,
          reason: 'missing $field',
        );
      }
      for (final field in ['roomId', 'sessionId', 'token']) {
        for (final value in [null, 7, 'guessable', '!' * 43, 'a' * 44]) {
          expect(
            () => BattleshipRtcInvitation.decode(
              jsonEncode({...original, field: value}),
              type: 'offer',
            ),
            throwsFormatException,
            reason: '$field=$value',
          );
        }
      }
      for (final field in ['ownFleet', 'enemyFleet', 'ships', 'password']) {
        expect(
          () => BattleshipRtcInvitation.decode(
            jsonEncode({...original, field: []}),
            type: 'offer',
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('rejects expired, future, invalid-time and oversized invitations', () {
    for (final at in [
      DateTime.now().subtract(const Duration(minutes: 31)),
      DateTime.now().add(const Duration(minutes: 3)),
    ]) {
      expect(
        () => BattleshipRtcInvitation.decode(
          invitation(createdAt: at).encode(),
          type: 'offer',
        ),
        throwsFormatException,
      );
    }
    final original = fields(invitation());
    for (final value in [null, 42, 'not a date']) {
      expect(
        () => BattleshipRtcInvitation.decode(
          jsonEncode({...original, 'createdAt': value}),
          type: 'offer',
        ),
        throwsFormatException,
      );
    }
    // Multibyte input checks the wire byte limit rather than character count.
    expect(
      () => BattleshipRtcInvitation.decode(
        jsonEncode({...original, 'sdp': 'v=0${'海' * 90000}'}),
        type: 'offer',
      ),
      throwsFormatException,
    );
    expect(
      () => BattleshipRtcInvitation.decode('[]', type: 'offer'),
      throwsFormatException,
    );
  });

  test(
    'answers must preserve room, session, token, timestamp and answer type',
    () {
      final offer = invitation();
      final original = fields(offer.answer('v=0\r\n'));
      for (final patch in <Map<String, Object?>>[
        {'roomId': battleshipSecret()},
        {'sessionId': battleshipSecret()},
        {'token': battleshipSecret()},
        {
          'createdAt': offer.createdAt
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        },
      ]) {
        final altered = BattleshipRtcInvitation.decode(
          jsonEncode({...original, ...patch}),
          type: 'answer',
        );
        expect(() => offer.validateAnswer(altered), throwsFormatException);
      }
      expect(() => offer.validateAnswer(offer), throwsFormatException);
    },
  );

  test(
    'prepareHost authenticates one local private replica without auto-start',
    () async {
      final room = BattleshipRtcRoom.host();
      addTearDown(room.close);
      room.coordinator!.session.randomizeFleet(BattleshipSeat.player1);
      room.coordinator!.session.randomizeFleet(BattleshipSeat.player2);
      final received = <String>[];
      room.replica.onWireMessage = received.add;
      await Future.wait([room.prepareHost(), room.prepareHost()]);
      expect(room.isHost, isTrue);
      expect(room.replica.connected, isTrue);
      expect(room.replica.started, isFalse);
      expect(room.replica.view!.seat, BattleshipSeat.player1);
      expect(room.replica.roomId, room.coordinator!.roomId);
      expect(room.coordinator!.playerCount, 1);
      expect(room.coordinator!.seats[1]['occupied'], isFalse);
      expect(room.replica.view!.ownFleet, hasLength(5));
      expect(room.replica.view!.enemyFleet, isEmpty);
      for (final raw in received) {
        final wire = jsonDecode(raw) as Map;
        if (wire['action'] != 'snapshot') continue;
        expect(wire['payload']['view']['enemyFleet'], isEmpty);
      }
      final seq = room.coordinator!.seq;
      await room.prepareHost();
      expect(room.coordinator!.seq, seq);
      await room.close();
      await expectLater(room.prepareHost(), throwsStateError);
    },
  );

  test(
    'host cannot replace a live guest invitation or disconnect its seat',
    () async {
      final room = BattleshipRtcRoom.host();
      final guest = BattleshipReplica();
      addTearDown(() async {
        await guest.close();
        await room.close();
      });
      await room.prepareHost();
      final (server, client) = MemoryTransport.pair();
      room.coordinator!.attach(server);
      await guest.bind(client, token: room.coordinator!.password);
      await expectLater(room.offer(), throwsStateError);
      expect(guest.connected, isTrue);
      expect(room.replica.connected, isTrue);
      expect(room.coordinator!.seats[1]['connected'], isTrue);
      expect(room.coordinator!.canStart, isTrue);
    },
  );

  test(
    'guest has no host authority and cannot switch authenticated rooms',
    () async {
      final room = BattleshipRtcRoom.guest();
      addTearDown(room.close);
      expect(room.isHost, isFalse);
      expect(room.coordinator, isNull);
      await expectLater(room.prepareHost(), throwsStateError);
      await expectLater(room.offer(), throwsStateError);
      await expectLater(
        room.accept(invitation().answer('v=0').encode()),
        throwsStateError,
      );
      room.replica.roomId = battleshipSecret();
      await expectLater(
        room.answer(invitation().encode()),
        throwsFormatException,
      );
      expect(room.replica.connected, isFalse);
    },
  );

  test(
    'unsupported native RTC fails without losing the host replica',
    () async {
      if (rtcSupported) return;
      final room = BattleshipRtcRoom.host();
      addTearDown(room.close);
      await expectLater(room.offer(), throwsUnsupportedError);
      expect(room.replica.connected, isTrue);
      expect(room.replica.view!.seat, BattleshipSeat.player1);
      expect(room.coordinator!.playerCount, 1);
      await room.prepareHost();
      await expectLater(room.offer(), throwsUnsupportedError);
      expect(room.coordinator!.playerCount, 1);
    },
  );
}
