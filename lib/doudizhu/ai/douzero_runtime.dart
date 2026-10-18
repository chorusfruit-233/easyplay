import 'dart:typed_data';

abstract interface class DouZeroRuntime {
  bool get supported;
  Future<Float32List> score(String role, Float32List x, Float32List z);
  Future<void> reset();
}
