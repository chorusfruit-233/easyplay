// Test-only bridge: never included in the production app.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:web/web.dart' as web;
import 'package:easyplay/doudizhu/doudizhu.dart';
import 'package:easyplay/doudizhu/doudizhu_match_controller.dart';
import 'package:easyplay/doudizhu/multiplayer/card_rtc_room.dart';
import 'package:easyplay/doudizhu/widgets/doudizhu_game_page.dart';
import 'package:easyplay/doudizhu/widgets/doudizhu_lobby_page.dart';

CardRtcRoom? room;
DouDizhuMatchController? controller;
final wires = <String>[];
Future<void> until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('state timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Three-player RTC smoke'))),
    ),
  );
  final bridge = JSObject();
  bridge['offer'] = ((JSNumber target, JSBoolean ai) => _offer(
    target.toDartInt,
    ai.toDart,
  ).toJS).toJS;
  bridge['answer'] = ((JSString text) => _answer(text.toDart).toJS).toJS;
  bridge['accept'] =
      ((JSString text) => room!.accept(text.toDart).then((_) => ''.toJS).toJS)
          .toJS;
  bridge['state'] = (() => jsonEncode({
    'connected': room?.replica.connected ?? false,
    'seq': room?.replica.seq,
    'roomId': room?.replica.roomId,
    'view': room?.replica.view?.toWire(),
    'seats': room?.replica.seats,
    'rematch': room?.replica.rematch,
    'error': room?.replica.error,
  }).toJS).toJS;
  bridge['action'] = ((JSString name) => _action(
    name.toDart,
  ).then((_) => ''.toJS).toJS).toJS;
  bridge['disconnect'] =
      (() => room!.replica.disconnect().then((_) => ''.toJS).toJS).toJS;
  bridge['wire'] = (() => jsonEncode(wires).toJS).toJS;
  bridge['close'] = (() => _close().then((_) => ''.toJS).toJS).toJS;
  bridge['lobby'] = (() {
    runApp(
      const MaterialApp(
        key: ValueKey('doudizhu-lobby'),
        home: DouDizhuLobbyPage(rtc: true),
      ),
    );
  }).toJS;
  bridge['mount'] = (() {
    controller?.dispose();
    controller = DouDizhuMatchController.network(room!.replica);
    runApp(
      MaterialApp(
        key: const ValueKey('doudizhu-game'),
        home: DouDizhuGamePage(controller: controller!),
      ),
    );
  }).toJS;
  web.window.setProperty('easyplayDoudizhuSmoke'.toJS, bridge);
}

void capture() {
  room!.replica.onWireMessage = wires.add;
}

Future<JSString> _offer(int target, bool ai) async {
  if (room == null) {
    room = CardRtcRoom.host(iceServers: []);
    await room!.prepareHost();
    capture();
    if (ai) room!.coordinator!.setAi(PlayerSeat.seat2, true);
  }
  return (await room!.offer(PlayerSeat.values[target])).toJS;
}

Future<JSString> _answer(String text) async {
  if (room == null) {
    room = CardRtcRoom.guest(iceServers: []);
    capture();
  }
  return (await room!.answer(text)).toJS;
}

Future<void> _action(String action) async {
  final r = room!.replica;
  await until(() => r.connected && r.error == null);
  final seq = r.seq;
  switch (action) {
    case 'start':
      r.send('start');
    case 'bid':
      r.send('bid', {'score': 3});
    case 'auto':
      final v = r.view!;
      if (v.publicState.phase == DouDizhuPhase.bidding) {
        r.send('bid', {'score': const BiddingPolicy().choose(v)});
      } else {
        final ids = await const DouDizhuAi().chooseAsync(v);
        r.send(ids.isEmpty ? 'pass' : 'play', {'cards': ids});
      }
    case 'rematch':
      r.send('rematch');
    case 'play':
      r.send('play', {
        'cards': [r.view!.hand.first],
      });
    default:
      throw ArgumentError(action);
  }
  await until(() => r.seq > seq || r.error != null);
  if (r.error != null) throw StateError(r.error!);
}

Future<void> _close() async {
  controller?.dispose();
  controller = null;
  await room?.close();
  room = null;
  wires.clear();
}
