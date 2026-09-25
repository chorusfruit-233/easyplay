import 'dart:convert';
import 'dart:typed_data';
import 'package:easyplay/go_storage.dart';
import 'package:easyplay/go_file_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryPicker extends FilePicker {
  Uint8List bytes = Uint8List(0);
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(name: 'test.sgf', size: bytes.length, bytes: bytes),
  ]);
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
    this.bytes = bytes!;
    return fileName;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'auto-save replaces each game and serializes concurrent updates',
    () async {
      await Future.wait([
        GoStorage.saveLast('first', gameId: 'one'),
        GoStorage.saveLast('after computer', gameId: 'one', vsComputer: true),
        GoStorage.saveLast('another game', gameId: 'two'),
      ]);
      expect(await GoStorage.records(), ['another game', 'after computer']);
      expect(await GoStorage.loadLast(), 'another game');
      await GoStorage.saveLast('undone', gameId: 'one', vsComputer: true);
      expect(await GoStorage.records(), ['undone', 'another game']);
      expect(await GoStorage.lastId(), 'one');
      expect(await GoStorage.lastComputerMode(), true);
      await GoStorage.clear();
      expect(await GoStorage.loadLast(), null);
      expect(await GoStorage.records(), isEmpty);
    },
  );

  test('history capped at 20 distinct games', () async {
    for (var i = 0; i < 22; i++) {
      await GoStorage.saveLast('game $i', gameId: '$i');
    }
    final records = await GoStorage.records();
    expect(records.length, 20);
    expect(records.first, 'game 21');
    expect(records.last, 'game 2');
  });

  test('legacy raw SGF entries remain readable', () async {
    SharedPreferences.setMockInitialValues({
      'easyplay.go_records': ['(;SZ[9])'],
    });
    await GoStorage.saveLast('(;SZ[19])', gameId: 'new');
    expect(await GoStorage.records(), ['(;SZ[19])', '(;SZ[9])']);
  });

  test('file save and import preserve Chinese and emoji in UTF-8', () async {
    final picker = MemoryPicker();
    FilePicker.platform = picker;
    const text = '(;SZ[19]PB[张三]C[围棋 🌟])';
    expect(await GoFileService.saveSgf(text), true);
    expect(picker.bytes, utf8.encode(text));
    expect(await GoFileService.pickSgf(), text);
  });
}
