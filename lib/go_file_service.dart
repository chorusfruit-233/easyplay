import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'record_file_service.dart';

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
    return RecordFileService.saveText(
      sgf,
      fileName: fileName,
      mimeType: fileName.toLowerCase().endsWith('.json')
          ? 'application/json;charset=utf-8'
          : 'application/x-go-sgf;charset=utf-8',
    );
  }
}
