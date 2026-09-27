import 'dart:convert';
import 'dart:typed_data';
import 'package:easyplay/go_storage.dart';
import 'package:easyplay/go_encoding.dart';
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

  test('saving the same game twice replaces it instead of piling up', () async {
    for (var i = 0; i < 22; i++) {
      await GoStorage.saveLast('move $i', gameId: 'one-game');
    }
    final records = await GoStorage.records();
    expect(records, ['move 21']);
  });

  test('legacy raw SGF entries remain readable', () async {
    SharedPreferences.setMockInitialValues({
      'easyplay.go_records': ['(;SZ[9])'],
    });
    await GoStorage.saveLast('(;SZ[19])', gameId: 'new');
    expect(await GoStorage.records(), ['(;SZ[19])', '(;SZ[9])']);
  });

  test('the library keeps every game, not just the newest few', () async {
    for (var i = 0; i < 25; i++) {
      await GoStorage.addRecord('(;SZ[19]C[game $i])');
    }
    final records = await GoStorage.recentRecords();
    expect(records, hasLength(25));
    // Newest first, and the very first one must still be there.
    expect(records.first.sgf, contains('game 24'));
    expect(records.last.sgf, contains('game 0'));
  });

  test('file save and import preserve Chinese and emoji in UTF-8', () async {
    final picker = MemoryPicker();
    FilePicker.platform = picker;
    const text = '(;SZ[19]PB[张三]C[围棋 🌟])';
    expect(await GoFileService.saveSgf(text), true);
    expect(picker.bytes, utf8.encode(text));
    // The picker hands back bytes, not text: deciding what they mean is the
    // encoding layer's job, not the file service's.
    final bytes = await GoFileService.pickSgfBytes();
    expect(bytes, isNotNull);
    final decoded = decodeKifuBytes(bytes!);
    expect(decoded.confident, isTrue);
    expect(decoded.text, text);
  });
}
