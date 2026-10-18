import 'dart:convert';

import 'package:easyplay/record_file_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/record_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryRecordFilePicker picker;

  setUp(() {
    picker = MemoryRecordFilePicker();
    FilePicker.platform = picker;
  });

  test('saves UTF-8 with the requested filename and extension', () async {
    const text = '(;GM[4]C[五子棋 🌟])';
    expect(
      await RecordFileService.saveText(
        text,
        fileName: 'gomoku-123.sgf',
        mimeType: 'application/x-go-sgf;charset=utf-8',
      ),
      isTrue,
    );
    expect(picker.savedFileName, 'gomoku-123.sgf');
    expect(picker.savedExtensions, ['sgf']);
    expect(utf8.decode(picker.savedBytes!), text);
  });

  test('reports a cancelled save and propagates picker failures', () async {
    picker.cancelled = true;
    expect(
      await RecordFileService.saveText(
        '{}',
        fileName: 'backup.json',
        mimeType: 'application/json;charset=utf-8',
      ),
      isFalse,
    );
    picker.saveError = StateError('storage unavailable');
    await expectLater(
      RecordFileService.saveText(
        '*',
        fileName: 'draughts.pdn',
        mimeType: 'text/plain;charset=utf-8',
      ),
      throwsStateError,
    );
  });
}
