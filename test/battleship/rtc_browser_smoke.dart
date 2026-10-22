// Test-only bridge: the production app never exports private test controls.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:easyplay/app_theme.dart';
import 'package:easyplay/battleship/battleship.dart';
import 'package:easyplay/battleship/battleship_match_controller.dart';
import 'package:easyplay/battleship/multiplayer/battleship_rtc_room.dart';
import 'package:easyplay/battleship/widgets/battleship_board.dart';
import 'package:easyplay/battleship/widgets/battleship_game_page.dart';
import 'package:easyplay/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:web/web.dart' as web;

BattleshipRtcRoom? room;
BattleshipMatchController? controller;
final wires = <String>[];

void visit(void Function(Element) action) {
  void walk(Element element) {
    action(element);
    element.visitChildElements(walk);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) {
    walk(root);
  }
}

Map<String, double>? rect(String key) {
  RenderBox? box;
  visit((element) {
    if (element.widget.key == ValueKey(key)) {
      final render = element.findRenderObject();
      if (render is RenderBox && render.attached && render.hasSize) {
        box = render;
      }
    }
  });
  final render = box;
  if (render == null) return null;
  final offset = render.localToGlobal(Offset.zero);
  return {
    'x': offset.dx,
    'y': offset.dy,
    'width': render.size.width,
    'height': render.size.height,
  };
}

Map<String, int> visibleFleets() {
  final fleets = <String, int>{};
  visit((element) {
    final widget = element.widget;
    if (widget is BattleshipBoard) fleets[widget.id] = widget.fleet.length;
  });
  return fleets;
}

void mount() {
  final current = controller;
  if (current == null) throw StateError('No test controller');
  runApp(
    MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromScheme(
        ColorScheme.fromSeed(seedColor: AppTheme.defaultSeed),
      ),
      home: BattleshipGamePage(controller: current),
    ),
  );
}

Future<void> close() async {
  runApp(const SizedBox());
  await WidgetsBinding.instance.endOfFrame;
  controller?.dispose();
  controller = null;
  await room?.close();
  room = null;
  wires.clear();
}

Future<String> offer() async {
  if (room == null) {
    room = BattleshipRtcRoom.host(iceServers: []);
    room!.replica.onWireMessage = wires.add;
    await room!.prepareHost();
  }
  return room!.offer();
}

Future<String> answer(String text) async {
  room ??= BattleshipRtcRoom.guest(iceServers: []);
  room!.replica.onWireMessage = wires.add;
  return room!.answer(text);
}

Future<void> action(String name, Map<String, Object?> payload) async {
  final replica = room!.replica;
  final before = replica.seq;
  if (name == 'auto') {
    replica.send('fire', {'cell': BattleshipAi().choose(replica.view!)});
  } else {
    replica.send(name, payload);
  }
  await replica.waitForSnapshot((r) => r.seq > before || r.error != null);
  if (replica.error != null) throw StateError(replica.error!);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const MaterialApp(home: Scaffold(body: Text('Battleship smoke'))));
  final api = JSObject();
  api['offer'] = (() => offer().then((text) => text.toJS).toJS).toJS;
  api['answer'] = ((JSString text) => answer(
    text.toDart,
  ).then((text) => text.toJS).toJS).toJS;
  api['accept'] =
      ((JSString text) => room!.accept(text.toDart).then((_) => ''.toJS).toJS)
          .toJS;
  api['action'] = ((JSString name, JSString payload) => action(
    name.toDart,
    Map<String, Object?>.from(jsonDecode(payload.toDart) as Map),
  ).then((_) => ''.toJS).toJS).toJS;
  api['state'] = (() => jsonEncode({
    'connected': room?.replica.connected ?? controller?.connected ?? false,
    'started': room?.replica.started,
    'seq': room?.replica.seq,
    'round': room?.replica.round,
    'roomId': room?.replica.roomId,
    'seats': room?.replica.seats,
    'rematch': room?.replica.rematch,
    'error': room?.replica.error ?? controller?.error,
    'view': (controller?.view ?? room?.replica.view)?.toWire(),
    'excludedCells':
        (controller?.view ?? room?.replica.view)?.excludedCells.toList() ?? [],
    'covered': controller?.covered ?? false,
    'thinking': controller?.thinking ?? false,
    'visibleFleets': visibleFleets(),
  }).toJS).toJS;
  api['wire'] = (() => jsonEncode(wires).toJS).toJS;
  api['rect'] = ((JSString key) => jsonEncode(rect(key.toDart)).toJS).toJS;
  api['disconnect'] =
      (() => room!.replica.disconnect().then((_) => ''.toJS).toJS).toJS;
  api['mount'] = (() {
    controller?.dispose();
    controller = BattleshipMatchController.network(room!.replica);
    mount();
  }).toJS;
  api['local'] = ((JSBoolean hotseat) => close().then((_) {
    controller = hotseat.toDart
        ? BattleshipMatchController.hotseat()
        : BattleshipMatchController.singlePlayer(
            aiDelay: const Duration(seconds: 2),
          );
    mount();
    return ''.toJS;
  }).toJS).toJS;
  api['active'] = ((JSBoolean active) => controller!.setActive(
    active.toDart,
  )).toJS;
  api['home'] = (() => close().then((_) {
    runApp(const EasyPlayApp());
    return ''.toJS;
  }).toJS).toJS;
  api['close'] = (() => close().then((_) => ''.toJS).toJS).toJS;
  web.window.setProperty('easyplayBattleshipSmoke'.toJS, api);
}
