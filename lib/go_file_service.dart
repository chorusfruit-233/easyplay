import 'dart:typed_data';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'go_download_native.dart'
    if (dart.library.js_interop) 'go_download_web.dart';

class GoFileService {
  /// The raw bytes of a picked kifu.
  ///
  /// Deliberately undecoded: an SGF can arrive in any of the CJK encodings, so
  /// deciding what the bytes mean belongs to [decodeKifuBytes], not here.
  static Future<Uint8List?> pickSgfBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sgf'],
      withData: true,
    );
    if (result == null) return null;
    return result.files.single.bytes;
  }

  static Future<bool> saveSgf(
    String sgf, {
    String fileName = 'easyplay-game.sgf',
  }) async {
    return downloadSgf(Uint8List.fromList(utf8.encode(sgf)), fileName);
  }
}
