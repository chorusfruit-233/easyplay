// A separate Flutter target for real RTC tests; never part of the shipped app.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:easyplay/lan/rtc_lobby_page.dart';
import 'package:easyplay/draughts/draughts_variant.dart';
import 'package:easyplay/gomoku/gomoku_variant.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/rtc_manual_signaling.dart';
import 'package:easyplay/lan/rtc_room.dart';
import 'package:easyplay/lan/rtc_transport.dart';
import 'package:easyplay/lan/rtc_ice_config.dart';

@JS('easyplayRtcSmoke')
external set _api(JSObject value);
RtcRoom? _room;
Future<void>? _joining;
int _padding = 0;
Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 30));
GomokuVariant gomokuVariantFor(String game) => game == 'gomoku-standard'
    ? GomokuVariant.standard
    : game == 'gomoku-renju'
    ? GomokuVariant.renju
    : GomokuVariant.freestyle;

Future<String> offer(String game) async {
  await _room?.close();
  final variant = DraughtsVariant.values
      .where((v) => v.name == game)
      .firstOrNull;
  final invite = RtcInvitation.offer(
    variant == null
        ? (game.startsWith('gomoku') ? 'gomoku' : game)
        : 'draughts',
    'v=0',
    variant: variant,
    gomokuVariant: gomokuVariantFor(game),
  );
  final room = _room = RtcRoom.host(invite);
  await room.prepareHost();
  room.peer = RtcPeer(iceServers: []);
  final sdp = await room.peer!.createOffer();
  room.invitation = RtcInvitation(
    sessionId: invite.sessionId,
    token: invite.token,
    game: invite.game,
    variant: invite.variant,
    gomokuVariant: invite.gomokuVariant,
    goConfig: invite.goConfig,
    type: 'offer',
    sdp: sdp,
  );
  return room.invitation.encode();
}

Future<String> resumeOffer() async {
  final room = _room!;
  await room.peer!.close();
  await tick();
  final old = room.invitation;
  room.peer = RtcPeer(iceServers: []);
  final sdp = await room.peer!.createOffer();
  room.invitation = RtcInvitation(
    sessionId: old.sessionId,
    token: old.token,
    game: old.game,
    variant: old.variant,
    gomokuVariant: old.gomokuVariant,
    goConfig: old.goConfig,
    type: 'offer',
    sdp: sdp,
  );
  return room.invitation.encode();
}

Future<String> answer(String raw) async {
  await _room?.close();
  final invite = RtcInvitation.decode(raw, expectedType: 'offer');
  final room = _room = RtcRoom.guest(invite);
  room.peer = RtcPeer(iceServers: []);
  _padding = 0;
  room.client.messages.listen((message) {
    if (message.body['padding'] is String) {
      _padding = (message.body['padding'] as String).length;
    }
  });
  final sdp = await room.peer!.createAnswer(invite.sdp);
  _joining = () async {
    await room.attachPeer(await room.peer!.transport);
  }();
  unawaited(_joining!.then<void>((_) {}, onError: (Object _) {}));
  return invite.answer(sdp).encode();
}

Future<void> accept(String raw) async {
  final room = _room!;
  final reply = RtcInvitation.decode(raw, expectedType: 'answer');
  room.invitation.validateAnswer(reply);
  await room.peer!.acceptAnswer(reply.sdp);
  await room.attachPeer(await room.peer!.transport);
  if (room.coordinator!.playerCount != 2) {
    await room.coordinator!.playerCounts
        .firstWhere((n) => n == 2)
        .timeout(const Duration(seconds: 10));
  }
}

Future<String> action(String name) async {
  if (_joining != null && !_room!.isHost) await _joining;
  final room = _room!, client = _room!.client;
  switch (name) {
    case 'start':
      room.coordinator!.startMatch();
    case 'move':
      final Map<String, Object?> move;
      if (client.isXiangqi) {
        move = {'game': 'xiangqi', 'move': 'h2e2'};
      } else if (client.isChess) {
        move = {'move': 'e2e4'};
      } else if (client.draughtsVariant != null) {
        move = {
          'path': room.coordinator!.draughtsAuthority!.session
              .legalMoves()
              .first
              .path
              .map((c) => [c.row, c.col])
              .toList(),
        };
      } else {
        move = {
          'cell': [3, 3],
        };
      }
      client.send(
        LanMessage(LanMessageType.move, client.seq + 1, {
          'side': LanMessage.sideCode(client.side!),
          ...move,
        }),
      );
    case 'pass':
      client.send(
        LanMessage(LanMessageType.pass, client.seq + 1, {
          'side': LanMessage.sideCode(client.side!),
        }),
      );
    case 'score':
      client.send(
        LanMessage(LanMessageType.scoreProposal, client.seq + 1, {
          'side': LanMessage.sideCode(client.side!),
          'deadStones': [],
        }),
      );
    case 'scoreAccept':
      client.send(
        LanMessage(LanMessageType.scoreAccept, client.seq + 1, {
          'side': LanMessage.sideCode(client.side!),
          'requestSeq': client.seq,
        }),
      );
    case 'resign':
      client.send(
        LanMessage(LanMessageType.resign, client.seq + 1, {
          'side': LanMessage.sideCode(client.side!),
        }),
      );
    case 'request':
      client.send(
        LanMessage(LanMessageType.rematchRequest, client.seq + 1, {
          'side': LanMessage.sideCode(client.side!),
        }),
      );
    case 'accept':
      client.send(
        LanMessage(LanMessageType.rematchAccept, client.seq + 1, {
          'side': LanMessage.sideCode(client.side!),
          'requestSeq': client.seq,
        }),
      );
    case 'large':
      final sync = room.coordinator!.sync(
        LanMessage(LanMessageType.stateRequest, client.seq, {'lastSeq': 0}),
      );
      final transport = await room.peer!.transport;
      transport.send(
        LanMessage(sync.type, sync.seq, {
          ...sync.body,
          'padding': '棋局🙂' * 30000,
        }),
      );
    case 'close':
      await room.peer!.close();
  }
  await tick();
  return state();
}

String state() {
  final room = _room!, client = room.client;
  return jsonEncode({
    'seq': client.seq,
    'started': client.started,
    'side': client.side?.name,
    'padding': _padding,
    'signature':
        client.xiangqiReplica?.session.fen ??
        client.chessReplica?.session.fen ??
        client.draughtsReplica?.session.position.signature(
          client.draughtsReplica!.session.turn,
        ) ??
        (client.gomokuReplica == null
            ? null
            : jsonEncode(client.gomokuReplica!.session.toJson())) ??
        client.replica?.sgf,
  });
}

// Optional live-network check: return only counts, never SDP or addresses.
Future<String> stunProbe(String urls) async {
  final peer = RtcPeer(
    iceServers: urls.isEmpty ? null : parseRtcStunServers(urls),
  );
  final watch = Stopwatch()..start();
  try {
    final sdp = await peer.createOffer();
    return jsonEncode({
      'srflx': RegExp(r' typ srflx').allMatches(sdp).length,
      'elapsedMs': watch.elapsedMilliseconds,
      'partial': peer.state.contains('部分 STUN'),
    });
  } finally {
    await peer.close();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  _api =
      {
            'offer': ((JSString game) => offer(
              game.toDart,
            ).then((s) => s.toJS).toJS).toJS,
            'resume': (() => resumeOffer().then((s) => s.toJS).toJS).toJS,
            'answer': ((JSString text) => answer(
              text.toDart,
            ).then((s) => s.toJS).toJS).toJS,
            'accept': ((JSString text) => accept(
              text.toDart,
            ).then((_) => true.toJS).toJS).toJS,
            'action': ((JSString name) => action(
              name.toDart,
            ).then((s) => s.toJS).toJS).toJS,
            'lobby': ((JSString game) => () async {
              await _room?.close();
              final name = game.toDart;
              final variant = DraughtsVariant.values
                  .where((v) => v.name == name)
                  .firstOrNull;
              runApp(
                MaterialApp(
                  key: ValueKey(name),
                  home: RtcLobbyPage(
                    game: variant == null
                        ? (name.startsWith('gomoku') ? 'gomoku' : name)
                        : 'draughts',
                    variant: variant,
                    gomokuVariant: gomokuVariantFor(name),
                    iceServers: [],
                  ),
                ),
              );
              await WidgetsBinding.instance.endOfFrame;
              return true.toJS;
            }().toJS).toJS,
            'stunProbe': ((JSString urls) => stunProbe(
              urls.toDart,
            ).then((s) => s.toJS).toJS).toJS,
            'state': (() => state().toJS).toJS,
          }.jsify()
          as JSObject;
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('RTC browser smoke ready'))),
    ),
  );
}
