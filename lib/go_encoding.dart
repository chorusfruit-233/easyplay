import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as legacy;
import 'package:enough_convert/big5.dart';
import 'package:flutter/material.dart';

import 'go_file_service.dart';
import 'go_sgf.dart';

/// A text encoding a kifu can arrive in.
///
/// `dart:convert` only knows UTF-8, Latin-1 and ASCII, so the CJK encodings old
/// kifu files use come from `charset` (GBK, Shift_JIS, EUC-JP) and
/// `enough_convert` (Big5) — both pure Dart, so imports work on every platform.
class GoTextEncoding {
  const GoTextEncoding(
    this.id,
    this.label,
    this.codec, {
    this.aliases = const [],
  });

  final String id;
  final String label;
  final Encoding codec;

  /// Names an SGF `CA[...]` property may use for this encoding.
  final List<String> aliases;

  /// True for the one encoding that needs no guessing.
  bool get isUtf8 => id == 'utf-8';
}

/// The encodings offered when importing, most likely first.
final List<GoTextEncoding> goKifuEncodings = List.unmodifiable([
  GoTextEncoding(
    'utf-8',
    'UTF-8',
    utf8,
    aliases: ['utf8', 'unicode-1-1-utf-8'],
  ),
  GoTextEncoding(
    'gbk',
    '简体中文 (GBK)',
    legacy.gbk,
    aliases: [
      'gb2312',
      'gb_2312-80',
      'gb18030',
      'cp936',
      'chinese',
      'csgb2312',
    ],
  ),
  GoTextEncoding(
    'big5',
    '繁体中文 (Big5)',
    const Big5Codec(),
    aliases: ['big-5', 'bigfive', 'cp950', 'cn-big5'],
  ),
  GoTextEncoding(
    'shift_jis',
    '日文 (Shift_JIS)',
    legacy.shiftJis,
    aliases: [
      'sjis',
      'shift-jis',
      'shiftjis',
      'ms_kanji',
      'cp932',
      'windows-31j',
    ],
  ),
  GoTextEncoding(
    'euc-jp',
    '日文 (EUC-JP)',
    legacy.eucJp,
    aliases: ['eucjp', 'x-euc-jp', 'csEUCPkdFmtJapanese'],
  ),
  GoTextEncoding(
    'iso-8859-1',
    '西欧 (ISO-8859-1)',
    latin1,
    aliases: ['latin1', 'iso_8859-1', 'iso8859-1', 'windows-1252', 'cp1252'],
  ),
]);

GoTextEncoding get _utf8Encoding => goKifuEncodings.first;

/// The encoding with this id, or null.
GoTextEncoding? goEncodingById(String id) =>
    goKifuEncodings.where((encoding) => encoding.id == id).firstOrNull;

/// Looks an encoding up by any name an SGF or a person might use.
GoTextEncoding? goEncodingByName(String name) {
  final wanted = name.trim().toLowerCase().replaceAll('_', '-');
  if (wanted.isEmpty) return null;
  for (final encoding in goKifuEncodings) {
    if (encoding.id == wanted) return encoding;
    for (final alias in encoding.aliases) {
      if (alias.toLowerCase().replaceAll('_', '-') == wanted) return encoding;
    }
  }
  return null;
}

/// What a kifu's bytes turned out to be.
class GoDecodedKifu {
  const GoDecodedKifu({
    required this.text,
    required this.encoding,
    required this.confident,
    required this.reason,
  });

  final String text;
  final GoTextEncoding encoding;

  /// False when the bytes could belong to more than one encoding, in which case
  /// the caller has to ask rather than pick for the user.
  final bool confident;

  /// Why this encoding was chosen, shown in the picker.
  final String reason;
}

/// Turns a kifu's bytes into text.
///
/// Guessing is kept to cases that leave no room for doubt — a byte order mark, a
/// `CA[...]` declaration, or bytes that are valid UTF-8. Anything else is
/// reported as unconfirmed, because a wrong legacy guess produces readable but
/// meaningless text that the user has no way to notice.
GoDecodedKifu decodeKifuBytes(Uint8List bytes, {GoTextEncoding? using}) {
  if (using != null) {
    return GoDecodedKifu(
      text: _decode(using, bytes),
      encoding: using,
      confident: true,
      reason: '手动选择',
    );
  }
  if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
    return GoDecodedKifu(
      text: utf8.decode(bytes.sublist(3), allowMalformed: true),
      encoding: _utf8Encoding,
      confident: true,
      reason: 'UTF-8 BOM',
    );
  }
  for (final (mark, littleEndian, label) in const [
    ([0xFF, 0xFE], true, 'UTF-16 LE BOM'),
    ([0xFE, 0xFF], false, 'UTF-16 BE BOM'),
  ]) {
    if (_startsWith(bytes, mark)) {
      return GoDecodedKifu(
        text: _decodeUtf16(bytes.sublist(2), littleEndian: littleEndian),
        encoding: _utf8Encoding,
        confident: true,
        reason: label,
      );
    }
  }
  final declared = declaredEncoding(bytes);
  if (declared != null) {
    try {
      return GoDecodedKifu(
        text: _decode(declared, bytes),
        encoding: declared,
        confident: true,
        reason: '棋谱声明 CA[${declared.id}]',
      );
    } catch (_) {
      // A declaration the bytes do not honour is worse than none; fall through.
    }
  }
  try {
    return GoDecodedKifu(
      text: utf8.decode(bytes),
      encoding: _utf8Encoding,
      confident: true,
      reason: 'UTF-8',
    );
  } catch (_) {
    // Not UTF-8, so it is one of the legacy encodings and cannot be told apart
    // reliably: hand it to the picker.
  }
  return GoDecodedKifu(
    text: _guess(bytes),
    encoding: _guessedEncoding(bytes),
    confident: false,
    reason: '无法确定，请选择',
  );
}

/// The encoding named by the root node's `CA[...]` property, if there is one.
///
/// Only the ASCII head of the file is searched: the declaration is at the front
/// by construction, and looking further would start matching brackets inside
/// comments.
GoTextEncoding? declaredEncoding(Uint8List bytes) {
  const marker = 'CA[';
  final limit = bytes.length < 4096 ? bytes.length : 4096;
  final head = String.fromCharCodes(
    bytes.sublist(0, limit).map((byte) => byte < 0x80 ? byte : 0x2E),
  );
  final start = head.indexOf(marker);
  if (start < 0) return null;
  final end = head.indexOf(']', start + marker.length);
  if (end < 0) return null;
  return goEncodingByName(head.substring(start + marker.length, end));
}

/// Candidate encodings for the picker, most likely first.
///
/// The guess leads, because it is the one the preview starts on; encodings that
/// cannot read these bytes at all follow, still listed so a wrong guess can
/// always be overruled. UTF-8 is left out: reaching the picker means the bytes
/// already failed a strict UTF-8 decode.
List<GoTextEncoding> goEncodingCandidates(Uint8List bytes) {
  final readable = <GoTextEncoding>[];
  final unreadable = <GoTextEncoding>[];
  for (final encoding in goKifuEncodings) {
    if (encoding.isUtf8) continue;
    (_decodes(encoding, bytes) ? readable : unreadable).add(encoding);
  }
  final guess = _guessedEncoding(bytes);
  return [
    guess,
    for (final encoding in readable)
      if (encoding.id != guess.id) encoding,
    ...unreadable,
  ];
}

GoTextEncoding _guessedEncoding(Uint8List bytes) {
  final survivors = <GoTextEncoding>[];
  for (final encoding in goKifuEncodings) {
    if (encoding.isUtf8) continue;
    if (!_decodes(encoding, bytes)) continue;
    survivors.add(encoding);
    // Kana belong to Japanese text alone, so a candidate that produces them is
    // the Japanese one whatever order the list happens to be in.
    if (_hasKana(_decode(encoding, bytes))) return encoding;
  }
  // Nothing distinguishes the survivors, so the list order decides. This is
  // only a default for the picker: the preview is what settles it.
  return survivors.isEmpty ? goKifuEncodings[1] : survivors.first;
}

bool _hasKana(String text) {
  for (final unit in text.codeUnits) {
    if (unit >= 0x3040 && unit <= 0x30FF) return true;
  }
  return false;
}

String _guess(Uint8List bytes) {
  final encoding = _guessedEncoding(bytes);
  try {
    return _decode(encoding, bytes);
  } catch (_) {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

/// Whether the bytes decode cleanly and look like text rather than mojibake.
///
/// Two failures are worth catching: bytes the codec rejects, and the half-width
/// katakana a Shift_JIS table produces when it is fed another encoding's bytes.
/// Real kifu text is never half-width katakana.
bool _decodes(GoTextEncoding encoding, Uint8List bytes) {
  try {
    final text = _decode(encoding, bytes);
    if (text.contains('\uFFFD')) return false;
    for (final unit in text.codeUnits) {
      if (unit >= 0xFF61 && unit <= 0xFF9F) return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

String _decode(GoTextEncoding encoding, Uint8List bytes) =>
    encoding.isUtf8 ? utf8.decode(bytes) : encoding.codec.decode(bytes);

/// UTF-16 is not in `dart:convert`; the bytes are already known to be UTF-16, so
/// this only has to pair them up. Surrogates pass through as-is and
/// [String.fromCharCodes] joins them.
String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | bytes[i + 1] << 8
          : bytes[i] << 8 | bytes[i + 1],
    );
  }
  final text = String.fromCharCodes(units);
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// Asks for a kifu file and returns its text, or null when the user backs out.
///
/// The encoding picker only appears when [decodeKifuBytes] could not identify
/// the bytes on its own.
Future<String?> pickKifuText(BuildContext context) async {
  final bytes = await GoFileService.pickSgfBytes();
  if (bytes == null || bytes.isEmpty) return null;
  final decoded = decodeKifuBytes(bytes);
  if (decoded.confident) return decoded.text;
  if (!context.mounted) return null;
  return showKifuEncodingPicker(context, bytes: bytes, guess: decoded);
}

/// Lets the user pick the encoding, previewing what it produces.
///
/// Returns the decoded text, or null when cancelled.
Future<String?> showKifuEncodingPicker(
  BuildContext context, {
  required Uint8List bytes,
  required GoDecodedKifu guess,
}) => showDialog<String>(
  context: context,
  builder: (context) => _EncodingPickerDialog(bytes: bytes, guess: guess),
);

/// The dialog behind [showKifuEncodingPicker]. Separate so it can be opened on
/// its own — and tested — without a platform file picker.
class KifuEncodingDialog extends StatelessWidget {
  const KifuEncodingDialog({
    super.key,
    required this.bytes,
    required this.guess,
  });

  final Uint8List bytes;
  final GoDecodedKifu guess;

  @override
  Widget build(BuildContext context) =>
      _EncodingPickerDialog(bytes: bytes, guess: guess);
}

class _EncodingPickerDialog extends StatefulWidget {
  const _EncodingPickerDialog({required this.bytes, required this.guess});

  final Uint8List bytes;
  final GoDecodedKifu guess;

  @override
  State<_EncodingPickerDialog> createState() => _EncodingPickerDialogState();
}

class _EncodingPickerDialogState extends State<_EncodingPickerDialog> {
  late GoTextEncoding _encoding = widget.guess.encoding;

  /// The started-on encoding first, then the rest in guessed order.
  ///
  /// Built from the selection rather than from the bytes alone so the dropdown
  /// always contains the value it is showing — UTF-8 included, when that is what
  /// the bytes turned out to be.
  late final List<GoTextEncoding> _candidates = [
    _encoding,
    for (final encoding in goEncodingCandidates(widget.bytes))
      if (encoding.id != _encoding.id) encoding,
  ];

  /// Decodes and parses with the current choice, so the dialog can say whether
  /// the pick is any good before anything is written to the library.
  (String text, String? error) get _preview {
    try {
      final text = decodeKifuBytes(widget.bytes, using: _encoding).text;
      try {
        GoSgf.importGame(text);
        return (text, null);
      } catch (error) {
        return (text, '棋谱无法解析：$error');
      }
    } catch (error) {
      return ('', '该编码无法读取这个文件：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (text, error) = _preview;
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('选择文件编码'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.guess.reason,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _encoding.id,
                decoration: const InputDecoration(labelText: '文件编码'),
                items: [
                  for (final encoding in _candidates)
                    DropdownMenuItem(
                      value: encoding.id,
                      child: Text(encoding.label),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _encoding = goEncodingById(value ?? '') ?? _encoding;
                }),
              ),
              const SizedBox(height: 16),
              Text('预览', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _snippet(text),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  style: TextStyle(fontSize: 12, color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: error == null ? () => Navigator.pop(context, text) : null,
          child: const Text('导入'),
        ),
      ],
    );
  }

  /// A kifu's SGF is mostly punctuation, so the preview collapses whitespace and
  /// shows the head, which is where the players, date and comments sit.
  static String _snippet(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return '（空）';
    return collapsed.length > 240
        ? '${collapsed.substring(0, 240)}…'
        : collapsed;
  }
}
