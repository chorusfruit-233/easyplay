import 'dart:typed_data';
import 'douzero_runtime.dart';

DouZeroRuntime createDouZeroRuntime() => _UnsupportedRuntime();

class _UnsupportedRuntime implements DouZeroRuntime {
  @override
  bool get supported => false;
  @override
  Future<Float32List> score(String role, Float32List x, Float32List z) =>
      Future.error(UnsupportedError('DouZero is available on Android and Web'));
  @override
  Future<void> reset() async {}
}
