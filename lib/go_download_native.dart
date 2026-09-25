import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<bool> downloadSgf(Uint8List bytes, String fileName) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '保存 SGF',
    fileName: fileName,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: ['sgf'],
  );
  return path != null;
}
