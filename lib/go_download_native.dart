import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<bool> downloadSgf(Uint8List bytes, String fileName) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '保存文件',
    fileName: fileName,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: [fileName.split('.').last],
  );
  return path != null;
}
