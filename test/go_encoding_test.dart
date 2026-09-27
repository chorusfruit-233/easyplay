import 'dart:convert';
import 'dart:typed_data';

import 'package:easyplay/go_encoding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bytes built from the standard tables, not from this project's decoders, so a
/// self-consistent but non-standard table cannot pass.
Uint8List _bytes(String hex) => Uint8List.fromList(
  hex.split(' ').map((byte) => int.parse(byte, radix: 16)).toList(),
);

/// A kifu whose player name is written in the given encoding.
Uint8List _kifu(String nameHex, {String? declared}) {
  final head = utf8.encode('(;GM[1]FF[4]SZ[19]${declared ?? ''}PB[');
  // ASCII only: the point of the sample is the one non-ASCII field, and a
  // legacy codec must be able to read every byte of the file.
  final tail = utf8.encode(']PW[White]C[first move])');
  return Uint8List.fromList([...head, ..._bytes(nameHex), ...tail]);
}

void main() {
  group('decoding', () {
    test('a byte order mark identifies the file outright', () {
      final utf8Bom = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('(;SZ[19]PB[张三])'),
      ]);
      final decoded = decodeKifuBytes(utf8Bom);
      expect(decoded.confident, isTrue);
      expect(decoded.reason, contains('BOM'));
      expect(decoded.text, '(;SZ[19]PB[张三])');

      // UTF-16 is not in dart:convert, so the pairing is ours to get right; a
      // surrogate pair must survive it.
      final utf16 = Uint8List.fromList([
        0xFF,
        0xFE,
        for (final char in '(;SZ[19]C[围棋])'.codeUnits) ...[
          char & 0xFF,
          char >> 8,
        ],
      ]);
      final fromUtf16 = decodeKifuBytes(utf16);
      expect(fromUtf16.confident, isTrue);
      expect(fromUtf16.text, '(;SZ[19]C[围棋])');
    });

    test('an SGF that declares its encoding is taken at its word', () {
      for (final (hex, declared, name) in const [
        ('88 E4 8E 52 97 54 91 BE', 'CA[Shift_JIS]', '井山裕太'),
        ('B0 E6 BB B3 CD B5 C2 C0', 'CA[EUC-JP]', '井山裕太'),
        ('BF C2 BD E0', 'CA[GB2312]', '柯洁'),
        ('B6 C2 B9 C5 B9 C5', 'CA[Big5]', '黑嘉嘉'),
      ]) {
        final decoded = decodeKifuBytes(_kifu(hex, declared: declared));
        expect(decoded.confident, isTrue, reason: declared);
        expect(decoded.reason, contains('CA'));
        expect(decoded.text, contains(name), reason: declared);
      }
    });

    test('valid UTF-8 needs no declaration', () {
      final decoded = decodeKifuBytes(
        Uint8List.fromList(utf8.encode('(;SZ[19]PB[张三]C[黑棋获胜])')),
      );
      expect(decoded.confident, isTrue);
      expect(decoded.text, contains('黑棋获胜'));
    });

    test('legacy bytes without a declaration are not guessed silently', () {
      // GBK, Big5 and EUC-JP all "decode" these bytes into something that is
      // readable but wrong, so the only safe answer is to ask.
      final decoded = decodeKifuBytes(_kifu('BF C2 BD E0'));
      expect(decoded.confident, isFalse);
      expect(decoded.reason, contains('无法确定'));
      // The guess is still offered first, so the common case is one tap.
      expect(goEncodingCandidates(_kifu('BF C2 BD E0')).first.id, 'gbk');
    });

    test('kana settle a guess that byte ranges cannot', () {
      // Kanji alone decode plausibly under several tables, but kana belong to
      // Japanese text only, so their presence decides it.
      final kana = Uint8List.fromList([
        ...utf8.encode('(;SZ[19]C['),
        ..._bytes('82 B1 82 F1 82 C9 82 BF 82 CD'), // こんにちは in Shift_JIS
        ...utf8.encode('])'),
      ]);
      expect(goEncodingCandidates(kana).first.id, 'shift_jis');
      expect(
        decodeKifuBytes(kana, using: goEncodingById('shift_jis')).text,
        contains('こんにちは'),
      );
    });

    test('encodings that cannot read the file are listed last', () {
      // Big5 answers these bytes with replacement characters and EUC-JP refuses
      // them, so both belong at the bottom; the real answer stays near the top.
      final sjis = _kifu('88 E4 8E 52 97 54 91 BE');
      final ids = goEncodingCandidates(sjis).map((e) => e.id).toList();
      expect(ids.indexOf('shift_jis'), lessThan(ids.indexOf('big5')));
      expect(ids.indexOf('shift_jis'), lessThan(ids.indexOf('euc-jp')));
      // Still listed, so a wrong guess can always be overruled.
      expect(ids, contains('big5'));
      expect(ids, isNot(contains('utf-8')));
    });

    test('an explicit choice always wins', () {
      final decoded = decodeKifuBytes(
        _kifu('BF C2 BD E0'),
        using: goEncodingById('gbk'),
      );
      expect(decoded.confident, isTrue);
      expect(decoded.reason, '手动选择');
      expect(decoded.text, contains('柯洁'));
    });

    test('encodings are found by any name a file might use', () {
      expect(goEncodingByName('GB2312')?.id, 'gbk');
      expect(goEncodingByName('gb18030')?.id, 'gbk');
      expect(goEncodingByName('Shift_JIS')?.id, 'shift_jis');
      expect(goEncodingByName('cp950')?.id, 'big5');
      expect(goEncodingByName('euc-jp')?.id, 'euc-jp');
      expect(goEncodingByName('UTF-8')?.id, 'utf-8');
      expect(goEncodingByName('no-such-charset'), isNull);
    });

    test('a declaration the bytes do not honour falls back to the picker', () {
      // Says UTF-8, is actually GBK: believing it would produce mojibake, so the
      // strict UTF-8 pass has to fail before the declaration is trusted.
      final decoded = decodeKifuBytes(
        _kifu('BF C2 BD E0', declared: 'CA[UTF-8]'),
      );
      expect(decoded.text, isNot(contains('\uFFFD')));
      expect(goEncodingByName('UTF-8')?.isUtf8, isTrue);
      expect(decoded.confident, isFalse);
    });
  });

  group('picker dialog', () {
    Future<void> open(
      WidgetTester tester,
      Uint8List bytes, {
      String? choose,
    }) async {
      final decoded = decodeKifuBytes(bytes);
      await tester.pumpWidget(
        MaterialApp(
          home: KifuEncodingDialog(bytes: bytes, guess: decoded),
        ),
      );
      await tester.pumpAndSettle();
      if (choose != null) {
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(choose).last);
        await tester.pumpAndSettle();
      }
    }

    testWidgets('previews the chosen encoding before anything is imported', (
      tester,
    ) async {
      await open(tester, _kifu('BF C2 BD E0'), choose: '简体中文 (GBK)');

      expect(find.textContaining('柯洁'), findsWidgets);
      // The SGF parses under the right choice, so the import is allowed.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '导入'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('anything that will not parse blocks the import', (
      tester,
    ) async {
      // The encoding is readable here but the content is not a kifu; the dialog
      // is the last gate before the library, so it has to say no.
      final notSgf = Uint8List.fromList(utf8.encode('this is not a kifu'));
      await open(tester, notSgf);

      expect(find.textContaining('棋谱无法解析'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '导入'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('cancelling returns nothing', (tester) async {
      String? result = 'unset';
      final bytes = _kifu('BF C2 BD E0');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showKifuEncodingPicker(
                  context,
                  bytes: bytes,
                  guess: decodeKifuBytes(bytes),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
