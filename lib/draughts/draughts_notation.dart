import '../game_session.dart' show Cell, Side;
import 'draughts_move.dart';
import 'draughts_record.dart';
import 'draughts_rules.dart';
import 'draughts_session.dart';
import 'draughts_variant.dart';

class DraughtsNotation {
  const DraughtsNotation._();

  static String fileName(DraughtsRecord record) {
    final identity = record.id ?? '${record.createdAt.microsecondsSinceEpoch}';
    final safeIdentity = identity.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final suffix = safeIdentity.length > 48
        ? safeIdentity.substring(0, 48)
        : safeIdentity;
    final date = record.createdAt.toUtc().toIso8601String().replaceAll(
      RegExp('[^0-9TZ]'),
      '',
    );
    return 'checkers_${record.variant.name}_${date}_$suffix.pdn';
  }

  static String exportPdn(DraughtsRecord record) {
    final rules = DraughtsRules.forVariant(record.variant);
    final result = _exportResult(record.result, rules);
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
      'GameType': _gameTypes[record.variant]!,
      'RulesVersion': '$draughtsRulesVersion',
      'EasyPlayNotationVersion': '2',
      'Result': result,
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
            .join(
              move.isCapture
                  ? (record.variant == DraughtsVariant.russian ? ':' : 'x')
                  : '-',
            ),
      );
      out.write(' ');
    }
    out.write(result);
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
    final gameType = _parseGameType(headers['GameType']);
    final namedVariant = _parseVariant(headers['Variant']);
    if (headers['Variant'] != null && namedVariant == null) {
      throw const FormatException('PDN variant is not supported');
    }
    final variant = namedVariant ?? gameType?.$1;
    if (variant == null) {
      throw const FormatException('PDN needs a supported Variant or GameType');
    }
    if (gameType != null && gameType.$1 != variant) {
      throw const FormatException('PDN Variant and GameType do not match');
    }
    final notationVersion = headers['EasyPlayNotationVersion'];
    if (notationVersion != null && notationVersion != '2') {
      throw const FormatException('PDN notation version is not supported');
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
    String? bodyResult;
    for (var token in tokens) {
      token = token.replaceFirst(RegExp(r'^\d+\.(?:\.\.)?$'), '');
      if (token.isEmpty) continue;
      token = token.replaceFirst(RegExp(r'^\d+\.+'), '');
      if (token.isEmpty) continue;
      if (_resultTokens.contains(token)) {
        if (bodyResult != null && bodyResult != token) {
          throw const FormatException('PDN has conflicting results');
        }
        bodyResult = token;
        continue;
      }
      final separator = token.contains('x')
          ? 'x'
          : token.contains(':')
          ? ':'
          : '-';
      final cells = token
          .split(separator)
          .map(
            (part) =>
                _parseSquare(part, rules, algebraic: gameType?.$2 ?? false),
          )
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
    final headerResult = headers['Result'];
    if (headerResult != null &&
        bodyResult != null &&
        headerResult != bodyResult) {
      throw const FormatException(
        'PDN header and movetext results do not match',
      );
    }
    final score = headerResult ?? bodyResult;
    // Before version 2, EasyPlay wrote its internal black-first result for
    // every variant and had no GameType tag. Keep those exported files readable.
    final modernResults =
        notationVersion != null ||
        gameType != null ||
        const {'2-0', '0-2', '1-1'}.contains(score);
    final result = _importResult(score, rules, modern: modernResults);
    final date =
        DateTime.tryParse((headers['Date'] ?? '').replaceAll('.', '-')) ??
        DateTime.now().toUtc();
    return DraughtsRecord(
      variant: variant,
      moves: moves,
      kind: kind,
      localSide: localSide,
      createdAt: date,
      result: result,
    );
  }

  // PDN GameType fields: id, first colour, width, height, notation, inversion.
  // https://wiegerw.github.io/pdn/gametype.html
  // Full descriptors declare the app's numeric Russian notation, white-first
  // Pool games and the Italian board orientation instead of relying on defaults.
  static const _gameTypes = <DraughtsVariant, String>{
    DraughtsVariant.english: '21,B,8,8,N1,0',
    DraughtsVariant.international: '20,W,10,10,N2,0',
    DraughtsVariant.brazilian: '26,W,8,8,N2,0',
    DraughtsVariant.russian: '25,W,8,8,N2,0',
    DraughtsVariant.pool: '23,W,8,8,N2,0',
    DraughtsVariant.italian: '22,W,8,8,N2,0',
    DraughtsVariant.spanish: '24,W,8,8,N2,0',
    DraughtsVariant.turkish: '30,W,8,8,A0,0',
  };

  static const _resultTokens = {
    '1-0',
    '0-1',
    '1/2-1/2',
    '2-0',
    '0-2',
    '1-1',
    '*',
  };

  // PDN uses the first player's score; International PDN3 awards two points.
  // https://wiegerw.github.io/pdn/pdntags.html#result-tag
  static String _exportResult(String? internal, DraughtsRules rules) {
    if (internal == null || internal == '*') return '*';
    final international = rules.variant == DraughtsVariant.international;
    if (internal == '1/2-1/2') return international ? '1-1' : '1/2-1/2';
    final winner = switch (internal) {
      '1-0' => Side.black,
      '0-1' => Side.white,
      _ => throw const FormatException('invalid draughts record result'),
    };
    return winner == rules.firstMove
        ? (international ? '2-0' : '1-0')
        : (international ? '0-2' : '0-1');
  }

  static String? _importResult(
    String? score,
    DraughtsRules rules, {
    required bool modern,
  }) {
    if (score == null || score == '*') return null;
    if (!_resultTokens.contains(score)) {
      throw const FormatException('invalid PDN result');
    }
    if (score == '1/2-1/2' || score == '1-1') return '1/2-1/2';
    if (!modern) return score;
    final firstWins = score == '1-0' || score == '2-0';
    final blackWins = firstWins == (rules.firstMove == Side.black);
    return blackWins ? '1-0' : '0-1';
  }

  static (DraughtsVariant, bool)? _parseGameType(String? value) {
    if (value == null) return null;
    final fields = value.split(',').map((part) => part.trim()).toList();
    final variant = switch (fields.first) {
      '20' => DraughtsVariant.international,
      '21' => DraughtsVariant.english,
      '22' => DraughtsVariant.italian,
      '23' => DraughtsVariant.pool,
      '24' => DraughtsVariant.spanish,
      '25' => DraughtsVariant.russian,
      '26' => DraughtsVariant.brazilian,
      '30' => DraughtsVariant.turkish,
      _ => throw const FormatException('PDN GameType is not supported'),
    };
    final defaults = _gameTypes[variant]!.split(',');
    // These PDN defaults differ from the app's explicitly exported settings.
    if (variant == DraughtsVariant.pool) {
      defaults[1] = 'B';
      defaults[4] = 'N1';
    } else if (variant == DraughtsVariant.italian) {
      defaults[5] = '1';
    } else if (variant == DraughtsVariant.russian ||
        variant == DraughtsVariant.brazilian) {
      defaults[4] = 'A0';
    } else if (variant == DraughtsVariant.spanish) {
      defaults[4] = 'N1';
      defaults[5] = '1';
    }
    if (fields.length > defaults.length) {
      throw const FormatException('invalid PDN GameType descriptor');
    }
    for (var i = 1; i < fields.length; i++) {
      if (fields[i].isNotEmpty) defaults[i] = fields[i];
    }
    final supported = _gameTypes[variant]!.split(',');
    final algebraic = defaults[4] == 'A0';
    for (final i in [1, 2, 3, 4, 5]) {
      if (defaults[i] != supported[i] &&
          !(i == 4 && variant == DraughtsVariant.russian && algebraic)) {
        throw const FormatException('PDN GameType settings are not supported');
      }
    }
    return (variant, algebraic);
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

  static Cell _parseSquare(
    String value,
    DraughtsRules rules, {
    bool algebraic = false,
  }) {
    if (algebraic || rules.geometry == BoardGeometry.orthogonalAllSquares) {
      final match = RegExp(
        r'^([a-z])(\d+)$',
        caseSensitive: false,
      ).firstMatch(value);
      if (match == null) {
        throw FormatException('invalid PDN coordinate: $value');
      }
      final row = int.parse(match.group(2)!);
      final col = match.group(1)!.toLowerCase().codeUnitAt(0) - 97;
      if (row < 1 || row > rules.boardSize || col >= rules.boardSize) {
        throw FormatException('invalid PDN coordinate: $value');
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
