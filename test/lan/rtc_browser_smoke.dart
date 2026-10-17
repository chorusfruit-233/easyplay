// A separate Flutter target for real RTC tests; never part of the shipped app.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:easyplay/board.dart';
import 'package:easyplay/go_placement.dart';
import 'package:easyplay/lan/lan_match_page.dart';
import 'package:easyplay/lan/rtc_lobby_page.dart';
import 'package:easyplay/draughts/draughts_variant.dart';
import 'package:easyplay/gomoku/gomoku_variant.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/gomoku/widgets/gomoku_lan_pages.dart';
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
String _lastError = '';
Future<T> _guard<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } catch (e) {
    _lastError = e.toString();
    rethrow;
  }
}

Future<String> offer(String game) => _guard(() => _offer(game));
Future<String> resumeOffer() => _guard(_resumeOffer);
Future<String> answer(String text) => _guard(() => _answer(text));
Future<String> action(String name) => _guard(() => _action(name));
Future<void> accept(String text, {bool delayBinding = false}) =>
    _guard(() => _accept(text, delayBinding: delayBinding));
Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 30));
GomokuVariant gomokuVariantFor(String game) => GomokuVariant.professional;

Future<String> _offer(String game) async {
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

Future<String> _resumeOffer() async {
  final room = _room!;
  await room.disconnectPeer();
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

Future<String> _answer(String raw) async {
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

Future<void> _accept(String raw, {bool delayBinding = false}) async {
  final room = _room!;
  final reply = RtcInvitation.decode(raw, expectedType: 'answer');
  room.invitation.validateAnswer(reply);
  await room.peer!.acceptAnswer(reply.sdp);
  final transport = await room.peer!.transport;
  if (delayBinding) {
    // Deliberately let guest hello arrive before the host room subscribes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  await room.attachPeer(transport);
  if (room.coordinator!.playerCount != 2) {
    await room.coordinator!.playerCounts
        .firstWhere((n) => n == 2)
        .timeout(const Duration(seconds: 10));
  }
}

Future<String> _action(String name) async {
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
          'cell': client.isGomoku ? [7, 7] : [3, 3],
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

// Observe the actual lobby's mounted game page, not the transport-only _room.
// This hook belongs only to this browser test target.
String uiGoState() {
  Element? boardElement;
  Board? board;
  LanMatchPage? page;
  BoardPainter? painter;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is LanMatchPage) page = widget;
    if (widget is Board) {
      boardElement = element;
      board = widget;
    }
    if (widget is CustomPaint && widget.painter is BoardPainter) {
      painter = widget.painter! as BoardPainter;
    }
    element.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  final view = board;
  final render = boardElement?.findRenderObject();
  if (view == null ||
      page == null ||
      painter == null ||
      render is! RenderBox ||
      !render.hasSize) {
    return jsonEncode({'ready': false});
  }
  final origin = render.localToGlobal(Offset.zero);
  final preview = painter!.preview;
  final session = view.session;
  return jsonEncode({
    'ready': true,
    'routeReady': ModalRoute.of(boardElement!)?.animation?.isCompleted != false,
    'seq': page!.connection.replica!.seq,
    'round': page!.connection.replica!.round,
    'side': page!.connection.side?.name,
    'turn': session.turn.name,
    'placementMode': view.placementMode.name,
    'preview': preview == null ? null : [preview.row, preview.col],
    'moves': [
      for (final move in session.moves)
        {
          'cell': [move.to.row, move.to.col],
          'side': move.side?.name,
          'pass': move.pass,
        },
    ],
    'stones': [
      for (var row = 0; row < session.size; row++)
        for (var col = 0; col < session.size; col++)
          if (session.board[row][col] case final piece?)
            {
              'cell': [row, col],
              'side': piece.side.name,
            },
    ],
    'size': session.size,
    'bounds': {
      'x': origin.dx,
      'y': origin.dy,
      'width': render.size.width,
      'height': render.size.height,
    },
  });
}

String uiGomokuState() {
  Element? element;
  GomokuBoard? board;
  GomokuLanMatchPage? page;
  dynamic painter;
  void visit(Element node) {
    final widget = node.widget;
    if (widget is GomokuLanMatchPage) page = widget;
    if (widget is GomokuBoard) {
      element = node;
      board = widget;
      void findPainter(Element child) {
        final candidate = child.widget;
        if (candidate is CustomPaint) painter = candidate.painter;
        child.visitChildren(findPainter);
      }

      node.visitChildren(findPainter);
    }
    node.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  final view = board, render = element?.findRenderObject();
  if (view == null || page == null || render is! RenderBox || !render.hasSize) {
    return jsonEncode({'ready': false});
  }
  final origin = render.localToGlobal(Offset.zero);
  final dynamic preview = painter?.preview;
  return jsonEncode({
    'ready': true,
    'routeReady': ModalRoute.of(element!)?.animation?.isCompleted != false,
    'seq': page!.connection.gomokuReplica!.seq,
    'side': page!.connection.side?.name,
    'phase': view.session.phase.name,
    'actor': view.session.actor.name,
    'exchanged': view.session.exchanged,
    'session': view.session.toJson(),
    'proposals': [
      for (final cell in view.session.proposals) [cell.row, cell.col],
    ],
    'preview': preview == null ? null : [preview.row, preview.col],
    'bounds': {
      'x': origin.dx,
      'y': origin.dy,
      'width': render.size.width,
      'height': render.size.height,
    },
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
            'acceptDelayed': ((JSString text) => accept(
              text.toDart,
              delayBinding: true,
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
              if (name == 'go') {
                await GoPlacementPreferences.save(GoPlacementMode.doubleTap);
              }
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
            'uiGoState': (() => uiGoState().toJS).toJS,
            'uiGomokuState': (() => uiGomokuState().toJS).toJS,
            'lastError': (() => _lastError.toJS).toJS,
          }.jsify()
          as JSObject;
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('RTC browser smoke ready'))),
    ),
  );
}
