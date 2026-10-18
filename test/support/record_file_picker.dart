import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class MemoryRecordFilePicker extends FilePicker {
  Uint8List? savedBytes;
  String? savedFileName;
  List<String>? savedExtensions;
  bool cancelled = false;
  Object? saveError;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedBytes = bytes;
    savedFileName = fileName;
    savedExtensions = allowedExtensions;
    if (saveError case final error?) throw error;
    return cancelled ? null : fileName;
  }
}
