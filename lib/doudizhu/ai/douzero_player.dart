import 'package:flutter/foundation.dart';
import '../doudizhu_model.dart';
import 'douzero_features.dart';
import 'douzero_runtime.dart';

/// Scores only app-validated actions; no upstream action can bypass our rules.
class DouZeroPlayer {
  DouZeroPlayer(this.runtime);
  final DouZeroRuntime runtime;

  Future<List<int>> choose(DouDizhuPlayerView view) async {
    final features = kIsWeb
        ? DouZeroFeatures.fromView(view)
        : await compute(_encode, view.toWire());
    final values = await runtime.score(features.role, features.x, features.z);
    if (values.length != features.actions.length ||
        values.any((value) => !value.isFinite)) {
      throw StateError('Invalid DouZero scores');
    }
    var best = 0;
    for (var i = 0; i < values.length; i++) {
      // Always take a legal immediate win, regardless of approximation error.
      if (features.actions[i].length == view.hand.length) {
        return features.actions[i];
      }
      if (values[i] > values[best]) best = i;
    }
    return features.actions[best];
  }
}

DouZeroFeatures _encode(Map<String, Object?> wire) =>
    DouZeroFeatures.fromView(DouDizhuPlayerView.fromWire(wire));
