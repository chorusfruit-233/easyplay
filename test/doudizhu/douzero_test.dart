import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:easyplay/doudizhu/doudizhu_model.dart';
import 'package:easyplay/doudizhu/ai/doudizhu_ai.dart';
import 'package:easyplay/doudizhu/ai/douzero_features.dart';
import 'package:easyplay/doudizhu/ai/douzero_player.dart';
import 'package:easyplay/doudizhu/ai/douzero_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

class _Scores implements DouZeroRuntime {
  _Scores(this.values);
  final Float32List values;
  @override
  bool get supported => true;
  @override
  Future<Float32List> score(String role, Float32List x, Float32List z) async =>
      values;
  @override
  Future<void> reset() async {}
}

class _Unavailable extends _Scores {
  _Unavailable() : super(Float32List(0));
  @override
  Future<Float32List> score(String role, Float32List x, Float32List z) async =>
      throw StateError('Model unavailable');
}

void main() {
  test(
    'model failure shows a warning and returns a legal compatibility play',
    () async {
      addTearDown(DouDizhuAi.retryEngine);
      final data =
          (jsonDecode(
                    File(
                      'test/doudizhu/fixtures/douzero_reference.json',
                    ).readAsStringSync(),
                  )
                  as Map)['cases'][0]
              as Map;
      final view = DouDizhuPlayerView.fromWire(
        Map<String, Object?>.from(data['view'] as Map),
      );
      final ai = DouDizhuAi(neuralPlayer: DouZeroPlayer(_Unavailable()));
      final play = await ai.chooseAsync(view);
      expect(DouDizhuAi.warning.value, contains('兼容策略'));
      expect(DouZeroFeatures.fromView(view).actions, contains(equals(play)));
      await DouDizhuAi.retryEngine();
      expect(DouDizhuAi.warning.value, isNull);
    },
  );
  final fixture =
      jsonDecode(
            File(
              'test/doudizhu/fixtures/douzero_reference.json',
            ).readAsStringSync(),
          )
          as Map;
  final cases = (fixture['cases'] as List).cast<Map>();
  for (final data in cases) {
    final view = DouDizhuPlayerView.fromWire(
      Map<String, Object?>.from(data['view'] as Map),
    );
    test('${data['name']} encodes identically to upstream GameEnv/get_obs', () {
      final features = DouZeroFeatures.fromView(view);
      expect(features.role, data['role']);
      expect(features.actions, data['actions']);
      expect(features.z.map((v) => v.toInt()).join(), data['z']);
      expect(
        sha256.convert(features.x.buffer.asUint8List()).toString(),
        data['xSha256'],
      );
      expect(
        features.x.take(features.width - 54).map((v) => v.toInt()).join(),
        data['xPrefix'],
      );
      expect(
        features.actions.every((ids) => ids.every(view.hand.contains)),
        isTrue,
      );
      expect(
        features.actions.any((ids) => ids.isEmpty),
        view.publicState.trick.seat != null,
      );
    });
    test('${data['name']} chooses the legal upstream best action', () async {
      final values = Float32List.fromList(
        (data['values'] as List).cast<num>().map((v) => v.toDouble()).toList(),
      );
      final best = values.indexOf(values.reduce((a, b) => a > b ? a : b));
      final player = DouZeroPlayer(_Scores(values));
      expect(await player.choose(view), data['actions'][best]);
    });
  }
  test(
    'old hosts without public history are rejected for compatibility policy',
    () {
      final wire = Map<String, Object?>.from(cases.first['view'] as Map);
      wire['public'] = Map<String, Object?>.from(wire['public'] as Map)
        ..remove('history');
      final view = DouDizhuPlayerView.fromWire(wire);
      expect(() => DouZeroFeatures.fromView(view), throwsStateError);
    },
  );
  test(
    'invalid output sizes and non-finite scores cannot select an action',
    () async {
      final view = DouDizhuPlayerView.fromWire(
        Map<String, Object?>.from(cases.first['view'] as Map),
      );
      final count = DouZeroFeatures.fromView(view).actions.length;
      for (final values in [
        Float32List(0),
        Float32List(count)..[0] = double.nan,
      ]) {
        await expectLater(
          DouZeroPlayer(_Scores(values)).choose(view),
          throwsStateError,
        );
      }
    },
  );
}
