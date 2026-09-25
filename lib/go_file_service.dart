import 'dart:typed_data';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'go_download_native.dart'
    if (dart.library.js_interop) 'go_download_web.dart';

class GoFileService {
  static Future<String?> pickSgf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sgf'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return null;
    return utf8.decode(result.files.single.bytes!);
  }

  static Future<bool> saveSgf(
    String sgf, {
    String fileName = 'easyplay-game.sgf',
  }) async {
    return downloadSgf(Uint8List.fromList(utf8.encode(sgf)), fileName);
  }
}
