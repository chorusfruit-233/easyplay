import 'dart:typed_data';

import 'go_model_storage_stub.dart'
    if (dart.library.io) 'go_model_storage_native.dart'
    if (dart.library.js_interop) 'go_model_storage_web.dart'
    as platform;

class GoModelStorage {
  static Future<void> save(String id, Uint8List bytes) =>
      platform.saveModel(id, bytes);
  static Future<Uint8List?> load(String id) => platform.loadModel(id);
  static Future<void> delete(String id) => platform.deleteModel(id);
}
