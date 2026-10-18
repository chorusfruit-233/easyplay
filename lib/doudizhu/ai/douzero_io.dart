import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'douzero_runtime.dart';

DouZeroRuntime createDouZeroRuntime() => _NativeRuntime();

class _NativeRuntime implements DouZeroRuntime {
  static const _channel = MethodChannel('easyplay/douzero');
  @override
  bool get supported => Platform.isAndroid;
  @override
  Future<Float32List> score(String role, Float32List x, Float32List z) async {
    final values = await _channel
        .invokeMethod<Float32List>('score', {'role': role, 'x': x, 'z': z})
        .timeout(const Duration(seconds: 45));
    if (values == null) throw StateError('DouZero returned no scores');
    return values;
  }

  @override
  Future<void> reset() => _channel.invokeMethod<void>('reset');
}
