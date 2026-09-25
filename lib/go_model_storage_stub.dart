import 'dart:typed_data';

Future<void> saveModel(String id, Uint8List bytes) =>
    Future.error(UnsupportedError('当前平台不支持 KataGo 模型存储'));
Future<Uint8List?> loadModel(String id) =>
    Future.error(UnsupportedError('当前平台不支持 KataGo 模型存储'));
Future<void> deleteModel(String id) =>
    Future.error(UnsupportedError('当前平台不支持 KataGo 模型存储'));
