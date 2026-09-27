import '../game_session.dart' show Cell, Side;
import 'draughts_move.dart';
import 'draughts_record.dart';
import 'draughts_rules.dart';
import 'draughts_session.dart';
import 'draughts_variant.dart';

class DraughtsNotation {
  const DraughtsNotation._();

  static String exportPdn(DraughtsRecord record) {
    final rules = DraughtsRules.forVariant(record.variant);
    final headers = <String, String>{
      'Event': 'EasyPlay game',
      'Site': 'EasyPlay',
      'Date':
          '${record.createdAt.year.toString().padLeft(4, '0')}.${record.createdAt.month.toString().padLeft(2, '0')}.${record.createdAt.day.toString().padLeft(2, '0')}',
      'Variant': switch (record.variant) {
        DraughtsVariant.english => 'English',
        DraughtsVariant.international => 'International',
        DraughtsVariant.brazilian => 'Brazilian',
        DraughtsVariant.russian => 'Russian',
        DraughtsVariant.pool => 'Pool',
        DraughtsVariant.italian => 'Italian',
        DraughtsVariant.spanish => 'Spanish',
        DraughtsVariant.turkish => 'Turkish',
      },
      'RulesVersion': '$draughtsRulesVersion',
      'Result': record.result ?? '*',
    };
    final out = StringBuffer();
    headers.forEach((key, value) => out.writeln('[$key "${_escape(value)}"]'));
    out.writeln();
    for (var i = 0; i < record.moves.length; i++) {
      if (i.isEven) out.write('${i ~/ 2 + 1}. ');
      final move = record.moves[i];
      out.write(
        move.path
            .map((cell) => _square(cell, rules))
            .join(move.isCapture ? 'x' : '-'),
      );
      out.write(' ');
    }
    out.write(record.result ?? '*');
    return out.toString().trimRight();
  }

  static DraughtsRecord importPdn(
    String source, {
    DraughtsGameKind kind = DraughtsGameKind.local,
    Side? localSide,
  }) {
    final headers = <String, String>{};
    final headerRegex = RegExp(
      r'^\s*\[(\w+)\s+"((?:\\.|[^"])*)"\]\s*$',
      multiLine: true,
    );
    for (final match in headerRegex.allMatches(source)) {
      headers[match.group(1)!] = match
          .group(2)!
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
    }
    final variant = _parseVariant(headers['Variant']);
    if (variant == null) {
      throw const FormatException('PDN needs a supported [Variant] header');
    }
    if (headers['RulesVersion'] != null &&
        headers['RulesVersion'] != '$draughtsRulesVersion') {
      throw const FormatException('PDN rules version is not supported');
    }
    final body = source.replaceAll(headerRegex, ' ');
    final tokens = body
        .replaceAll(RegExp(r'\{[^}]*\}|;[^\n]*|\([^)]*\)'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    final rules = DraughtsRules.forVariant(variant);
    final session = DraughtsSession(rules);
    final moves = <DraughtsMove>[];
    for (var token in tokens) {
      token = token.replaceFirst(RegExp(r'^\d+\.(?:\.\.)?$'), '');
      if (token.isEmpty ||
          const {'1-0', '0-1', '1/2-1/2', '*'}.contains(token)) {
        continue;
      }
      token = token.replaceFirst(RegExp(r'^\d+\.+'), '');
      if (token.isEmpty) continue;
      final separator = token.contains('x') ? 'x' : '-';
      final cells = token
          .split(separator)
          .map((part) => _parseSquare(part, rules))
          .toList();
      if (cells.length < 2) throw FormatException('invalid PDN move: $token');
      final move = session
          .legalMoves()
          .where(
            (candidate) =>
                candidate.path.length == cells.length &&
                List.generate(
                  cells.length,
                  (i) => candidate.path[i] == cells[i],
                ).every((v) => v),
          )
          .firstOrNull;
      if (move == null || !session.applyMove(move)) {
        throw FormatException('illegal PDN move for ${variant.name}: $token');
      }
      moves.add(move);
    }
    final date =
        DateTime.tryParse((headers['Date'] ?? '').replaceAll('.', '-')) ??
        DateTime.now().toUtc();
    return DraughtsRecord(
      variant: variant,
      moves: moves,
      kind: kind,
      localSide: localSide,
      createdAt: date,
      result: headers['Result'] == '*' ? null : headers['Result'],
    );
  }

  static String _square(Cell cell, DraughtsRules rules) {
    if (!rules.isPlayable(cell)) {
      throw const FormatException('PDN square is not playable');
    }
    if (rules.geometry == BoardGeometry.orthogonalAllSquares) {
      return '${String.fromCharCode(97 + cell.col)}${rules.boardSize - cell.row}';
    }
    final width = rules.boardSize ~/ 2;
    return '${cell.row * width + cell.col ~/ 2 + 1}';
  }

  static DraughtsVariant? _parseVariant(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'english' ||
      'american' ||
      'english / american' ||
      'english/american' ||
      'american checkers' ||
      'straight checkers' ||
      'checkers' => DraughtsVariant.english,
      'international' ||
      'international draughts' => DraughtsVariant.international,
      'brazilian' || 'brazilian draughts' => DraughtsVariant.brazilian,
      'russian' || 'russian draughts' => DraughtsVariant.russian,
      'pool' ||
      'pool checkers' ||
      'american pool checkers' => DraughtsVariant.pool,
      'italian' || 'italian draughts' => DraughtsVariant.italian,
      'spanish' || 'spanish draughts' => DraughtsVariant.spanish,
      'turkish' || 'turkish draughts' => DraughtsVariant.turkish,
      _ => null,
    };
  }

  static Cell _parseSquare(String value, DraughtsRules rules) {
    if (rules.geometry == BoardGeometry.orthogonalAllSquares) {
      final match = RegExp(
        r'^([a-z])(\d+)$',
        caseSensitive: false,
      ).firstMatch(value);
      if (match == null) {
        throw FormatException('invalid Turkish coordinate: $value');
      }
      final row = int.parse(match.group(2)!);
      final col = match.group(1)!.toLowerCase().codeUnitAt(0) - 97;
      if (row < 1 || row > rules.boardSize || col >= rules.boardSize) {
        throw FormatException('invalid Turkish coordinate: $value');
      }
      return Cell(rules.boardSize - row, col);
    }
    final number = int.tryParse(value);
    final count = rules.boardSize * rules.boardSize ~/ 2;
    if (number == null || number < 1 || number > count) {
      throw FormatException('invalid PDN square: $value');
    }
    final zero = number - 1;
    final row = zero ~/ (rules.boardSize ~/ 2);
    final offset = zero % (rules.boardSize ~/ 2);
    final col = row.isEven ? offset * 2 + 1 : offset * 2;
    return Cell(row, col);
  }

  static String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
