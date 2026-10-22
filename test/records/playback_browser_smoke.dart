// Independent test target; the production app has no fixtures or JS controls.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:easyplay/draughts/draughts.dart';
import 'package:easyplay/draughts/widgets/draughts_board.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_storage.dart';
import 'package:easyplay/gomoku/gomoku_session.dart';
import 'package:easyplay/gomoku/gomoku_storage.dart';
import 'package:easyplay/gomoku/widgets/gomoku_board.dart';
import 'package:easyplay/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

void visit(void Function(Element) action) {
  void walk(Element element) {
    action(element);
    element.visitChildElements(walk);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) walk(root);
}

Map<String, Object?> state() {
  final result = <String, Object?>{};
  visit((element) {
    final widget = element.widget;
    if (widget is Board) result['session'] = widget.session.moves.length;
    if (widget is GomokuBoard) {
      result['session'] = widget.session.toJson();
    }
    if (widget is DraughtsBoard) {
      result['session'] = widget.session.toJson();
    }
    if (widget is Text &&
        widget.key == const ValueKey('record-playback-progress')) {
      result['progress'] = widget.data;
    }
    if (widget is IconButton &&
        widget.key == const ValueKey('record-playback-toggle')) {
      result['playing'] = widget.tooltip == '暂停播放';
    }
  });
  return result;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  await GoStorage.addRecord(
    '(;GM[1]SZ[9]AB[aa]PL[W]C[让子与变着示例];W[dd]TR[dd]C[白方占角]'
    '(;B[ff];W[])(;B[ee]C[另一条变化]))',
  );
  final gomoku = GomokuSession()
    ..place(const Cell(7, 7))
    ..place(const Cell(6, 7))
    ..place(const Cell(5, 7))
    ..exchangeColors(true)
    ..place(const Cell(9, 7))
    ..declareProposals(2)
    ..exchangeColors(false)
    ..place(const Cell(6, 6))
    ..place(const Cell(7, 5))
    ..place(const Cell(7, 5))
    ..pass()
    ..pass();
  await GomokuStorage.save(
    GomokuRecord(
      id: 'playback-gomoku',
      createdAt: DateTime.utc(2026, 10, 22),
      session: gomoku,
    ),
  );
  final draughts = DraughtsSession(
    DraughtsRules.forVariant(DraughtsVariant.international),
  );
  for (var i = 0; i < 12; i++) {
    draughts.applyMove(draughts.legalMoves().first);
  }
  await DraughtsStorage.save(
    DraughtsRecord.fromSession(
      draughts,
      id: 'playback-draughts',
      createdAt: DateTime.utc(2026, 10, 22),
    ),
  );
  final api = JSObject();
  api['state'] = (() => jsonEncode(state()).toJS).toJS;
  api['storage'] =
      (() => SharedPreferences.getInstance()
              .then(
                (prefs) => jsonEncode({
                  for (final key in prefs.getKeys()) key: prefs.get(key),
                }).toJS,
              )
              .toJS)
          .toJS;
  web.window.setProperty('easyplayPlaybackSmoke'.toJS, api);
  runApp(const EasyPlayApp());
}
