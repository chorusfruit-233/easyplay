import 'dart:typed_data';

import 'package:flutter/services.dart';

const _channel = MethodChannel('easyplay/katago');

Future<void> saveModel(String id, Uint8List bytes) async {
  await _channel.invokeMethod<void>('storeModel', {'id': id, 'model': bytes});
}

Future<Uint8List?> loadModel(String id) async =>
    _channel.invokeMethod<Uint8List>('loadModel', {'id': id});

Future<void> deleteModel(String id) async {
  await _channel.invokeMethod<void>('deleteModel', {'id': id});
}
