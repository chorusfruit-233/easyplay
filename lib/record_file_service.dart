import 'dart:convert';
import 'dart:typed_data';

import 'record_download_native.dart'
    if (dart.library.js_interop) 'record_download_web.dart';

/// Saves a UTF-8 record through the platform file picker or browser download.
class RecordFileService {
  static Future<bool> saveText(
    String content, {
    required String fileName,
    required String mimeType,
  }) => downloadRecord(
    Uint8List.fromList(utf8.encode(content)),
    fileName,
    mimeType,
  );
}
