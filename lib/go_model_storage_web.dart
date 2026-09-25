import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('easyPlayStoreKataGoModel')
external JSPromise<JSString> _store(JSString id, JSString bytes);
@JS('easyPlayLoadKataGoModel')
external JSPromise<JSString> _load(JSString id);
@JS('easyPlayDeleteKataGoModel')
external JSPromise<JSString> _delete(JSString id);

Future<void> saveModel(String id, Uint8List bytes) async {
  await _store(id.toJS, base64Encode(bytes).toJS).toDart;
}

Future<Uint8List?> loadModel(String id) async {
  final encoded = (await _load(id.toJS).toDart).toDart;
  return encoded.isEmpty ? null : Uint8List.fromList(base64Decode(encoded));
}

Future<void> deleteModel(String id) async {
  await _delete(id.toJS).toDart;
}
