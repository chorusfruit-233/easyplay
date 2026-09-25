import 'game_session.dart';

class GoSgfNode {
  final Map<String, List<String>> properties;
  final List<GoSgfNode> children = [];
  GoSgfNode([Map<String, List<String>>? properties])
    : properties = properties ?? {};
  String? get comment => properties['C']?.first;
  GoSgfNode? get mainChild => children.isEmpty ? null : children.first;
}

class GoSgfRecord {
  final GoSgfNode root;
  const GoSgfRecord(this.root);
}

/// A playable path through an SGF tree. [choices] contains the child index
/// chosen at each branch point (in traversal order).
class GoSgfVariation {
  final List<int> choices;
  final int moveCount;
  final String label;
  const GoSgfVariation(this.choices, this.moveCount, this.label);
}

class _ImportedGame {
  final String source;
  final List<GameMove> moves;
  final List<int> choices;
  final int revision;
  _ImportedGame(this.source, GameSession game, this.choices)
    : moves = List.of(game.moves),
      revision = game.revision;
}

/// FF[4] tree codec. Unknown properties, comments and variations are retained.
/// Game replay selects the first variation; unsupported setup changes fail
/// explicitly rather than silently producing a different game.
class GoSgf {
  static final _imports = Expando<_ImportedGame>();

  static GoSgfRecord parseRecord(String sgf) =>
      GoSgfRecord(_TreeParser(sgf).parse());

  /// Lists each complete line in a record. The first item is the SGF main
  /// line; subsequent items are alternate branches in depth-first order.
  static List<GoSgfVariation> variations(String sgf) {
    final root = parseRecord(sgf).root;
    final result = <GoSgfVariation>[];
    void visit(GoSgfNode node, List<int> choices, int moves) {
      final hasMove =
          node.properties.containsKey('B') || node.properties.containsKey('W');
      final nextMoves = moves + (hasMove ? 1 : 0);
      if (node.children.isEmpty) {
        result.add(
          GoSgfVariation(
            List.unmodifiable(choices),
            nextMoves,
            result.isEmpty
                ? '主线（$nextMoves 手）'
                : '变例 ${result.length}（$nextMoves 手）',
          ),
        );
        return;
      }
      for (var i = 0; i < node.children.length; i++) {
        visit(
          node.children[i],
          node.children.length > 1 ? [...choices, i] : choices,
          nextMoves,
        );
      }
    }

    visit(root, const [], 0);
    return List.unmodifiable(result);
  }

  static String exportRecord(GoSgfRecord record) {
    final out = StringBuffer();
    void tree(GoSgfNode node) {
      out.write('(');
      while (true) {
        out.write(';');
        node.properties.forEach((key, values) {
          if (values.isEmpty) return;
          out.write(key);
          for (final value in values) {
            out.write('[${_escape(value)}]');
          }
        });
        if (node.children.length == 1) {
          node = node.children.single;
          continue;
        }
        for (final child in node.children) {
          tree(child);
        }
        break;
      }
      out.write(')');
    }

    tree(record.root);
    return out.toString();
  }

  static String exportGame(
    GameSession game, {
    String? event,
    String? playerBlack,
    String? playerWhite,
  }) {
    if (game.type != GameType.go) {
      throw ArgumentError('SGF export requires a Go session');
    }
    final c = game.goConfig;
    final imported = _imports[game];
    final reuse = imported != null && imported.revision == game.revision;
    final root = reuse ? parseRecord(imported.source).root : GoSgfNode();
    root.properties.addAll({
      'GM': ['1'],
      'FF': ['4'],
      'CA': ['UTF-8'],
      'SZ': ['${c.boardSize}'],
      'RU': [c.rules.sgfName],
      'KM': ['${c.komi}'],
    });
    if (!reuse) {
      if (c.handicap > 0) root.properties['HA'] = ['${c.handicap}'];
      for (final side in Side.values) {
        final points = <String>[];
        for (var r = 0; r < game.size; r++) {
          for (var col = 0; col < game.size; col++) {
            if (game.initialGoBoard[r][col]?.side == side) {
              points.add(_coord(Cell(r, col)));
            }
          }
        }
        if (points.isNotEmpty) {
          root.properties[side == Side.black ? 'AB' : 'AW'] = points;
        }
      }
      root.properties['PL'] = [game.initialGoTurn == Side.black ? 'B' : 'W'];
    }
    if (event != null) root.properties['EV'] = [event];
    if (playerBlack != null) root.properties['PB'] = [playerBlack];
    if (playerWhite != null) root.properties['PW'] = [playerWhite];

    var tail = root;
    var prefix = 0;
    if (reuse) {
      while (prefix < imported.moves.length &&
          prefix < game.moves.length &&
          identical(imported.moves[prefix], game.moves[prefix])) {
        prefix++;
      }
      final pathNodes = _followPath(root, imported.choices);
      final moveNodeIndexes = <int>[];
      for (var i = 0; i < pathNodes.length; i++) {
        final node = pathNodes[i];
        node.properties.remove('XDS');
        node.properties.remove('XSC');
        if (node.properties.containsKey('B') ||
            node.properties.containsKey('W')) {
          moveNodeIndexes.add(i);
        }
      }
      // Keep every sibling variation. Remove only the selected continuation
      // after the last move that still matches the edited game.
      final anchor = prefix == 0
          ? root
          : pathNodes[moveNodeIndexes[prefix - 1]];
      if (prefix < imported.moves.length) {
        final anchorIndex = prefix == 0 ? 0 : moveNodeIndexes[prefix - 1];
        if (anchorIndex + 1 < pathNodes.length) {
          anchor.children.remove(pathNodes[anchorIndex + 1]);
        }
        tail = anchor;
      } else {
        tail = pathNodes.isEmpty ? root : pathNodes.last;
      }
    }
    for (var i = prefix; i < game.moves.length; i++) {
      final move = game.moves[i];
      final side =
          move.side ??
          (i.isEven ? game.initialGoTurn : game.initialGoTurn.opponent);
      final node = GoSgfNode({
        side == Side.black ? 'B' : 'W': [move.pass ? '' : _coord(move.to)],
      });
      tail.children.add(node);
      tail = node;
    }
    // Application extension properties retain provisional scoring on restore.
    if (game.deadGoStones.isNotEmpty) {
      tail.properties['XDS'] = game.deadGoStones.map(_coord).toList();
    }
    if (game.goScoreConfirmed) {
      tail.properties['XSC'] = ['1'];
      final score = game.calculateGoScore();
      root.properties['RE'] = [
        score.winner == null
            ? '0'
            : '${score.winner == Side.black ? 'B' : 'W'}+${score.margin}',
      ];
    } else if (!reuse ||
        prefix != imported.moves.length ||
        prefix != game.moves.length) {
      root.properties.remove('RE');
    }
    return exportRecord(GoSgfRecord(root));
  }

  static GameSession importGame(String sgf, {List<int> variation = const []}) {
    final record = parseRecord(sgf);
    final root = record.root;
    String? value(String key) => root.properties[key]?.single;
    if ((value('GM') ?? '1') != '1') throw const FormatException('仅支持围棋 SGF');
    final size = int.tryParse(value('SZ') ?? '19');
    final handicap = int.tryParse(value('HA') ?? '0');
    final rules = _rules(value('RU'));
    final komi = double.tryParse(
      value('KM') ?? (rules == GoRuleSet.chinese ? '7.5' : '6.5'),
    );
    if (size == null || handicap == null || komi == null) {
      throw const FormatException('棋盘、贴目或让子格式无效');
    }
    final config = GoConfig(
      boardSize: [9, 13, 19].contains(size) ? size : 19,
      rules: rules,
      komi: komi.isFinite && komi >= -100 && komi <= 100 ? komi : 0,
      handicap: handicap >= 0 && handicap <= 9 ? handicap : 0,
    );
    // Validate before constructing a session; do not clamp unsupported values.
    if (![9, 13, 19].contains(size) ||
        handicap == 1 ||
        handicap < 0 ||
        handicap > 9 ||
        !komi.isFinite ||
        komi < -100 ||
        komi > 100) {
      throw const FormatException('仅支持9/13/19路、0或2–9让子及-100至100贴目');
    }
    final game = GameSession(GameType.go, goConfig: config);
    final stones = <Cell, Side>{};
    final explicitSetup =
        root.properties.containsKey('AB') || root.properties.containsKey('AW');
    if (!explicitSetup) {
      for (var r = 0; r < size; r++) {
        for (var c = 0; c < size; c++) {
          final piece = game.pieceAt(Cell(r, c));
          if (piece != null) stones[Cell(r, c)] = piece.side;
        }
      }
    }
    for (final side in Side.values) {
      for (final cell in _points(
        root.properties[side == Side.black ? 'AB' : 'AW'] ?? [],
        size,
      )) {
        if (stones.containsKey(cell)) throw const FormatException('摆子位置重复');
        stones[cell] = side;
      }
    }
    for (final cell in _points(root.properties['AE'] ?? [], size)) {
      stones.remove(cell);
    }
    Side parseSide(String raw) => switch (raw) {
      'B' => Side.black,
      'W' => Side.white,
      _ => throw const FormatException('PL 必须为 B 或 W'),
    };
    final first = value('PL') == null ? game.turn : parseSide(value('PL')!);
    game.setupGo(stones, first);
    GoSgfNode? node = root;
    GoSgfNode last = root;
    var branchChoice = 0;
    final pathNodes = <GoSgfNode>[];
    final moveNodeIndexes = <int>[];
    final selectedChoices = <int>[];
    while (node != null) {
      pathNodes.add(node);
      final p = node.properties;
      if (node != root && ['AB', 'AW', 'AE'].any(p.containsKey)) {
        throw const FormatException('此棋谱含中途摆子，请使用支持编辑局面的复盘工具');
      }
      if (p.containsKey('PL')) game.turn = parseSide(p['PL']!.single);
      if (p.containsKey('B') && p.containsKey('W')) {
        throw const FormatException('同一节点不能同时有黑白落子');
      }
      final color = p.containsKey('B')
          ? 'B'
          : p.containsKey('W')
          ? 'W'
          : null;
      if (color != null) {
        if (game.gameOver) throw const FormatException('连续停一手后的续弈尚不支持');
        final raw = p[color]!.single;
        game.turn = parseSide(color);
        final ok = raw.isEmpty || raw == 'tt'
            ? game.passGo()
            : game.placeGo(_decode(raw, size));
        if (!ok) {
          throw FormatException('第 ${game.moves.length + 1} 手不合法：$color[$raw]');
        }
        moveNodeIndexes.add(pathNodes.length - 1);
      }
      last = node;
      if (node.children.isEmpty) {
        node = null;
      } else if (node.children.length == 1) {
        node = node.children.single;
      } else {
        final selected = branchChoice < variation.length
            ? variation[branchChoice]
            : 0;
        if (selected < 0 || selected >= node.children.length) {
          throw const FormatException('所选 SGF 变化不存在');
        }
        selectedChoices.add(selected);
        branchChoice++;
        node = node.children[selected];
      }
    }
    for (final cell in _points(last.properties['XDS'] ?? [], size)) {
      if (game.pieceAt(cell) == null || !game.gameOver) {
        throw const FormatException('无效的死子标记');
      }
      game.deadGoStones.add(cell);
    }
    if (last.properties['XSC']?.first == '1') game.confirmGoScore();
    _imports[game] = _ImportedGame(exportRecord(record), game, selectedChoices);
    return game;
  }

  static List<GoSgfNode> _followPath(GoSgfNode root, List<int> choices) {
    final path = <GoSgfNode>[root];
    var choiceIndex = 0;
    var node = root;
    while (node.children.isNotEmpty) {
      final selected = node.children.length == 1
          ? 0
          : (choiceIndex < choices.length ? choices[choiceIndex++] : 0);
      if (selected < 0 || selected >= node.children.length) break;
      node = node.children[selected];
      path.add(node);
    }
    return path;
  }

  static Iterable<Cell> _points(List<String> values, int size) sync* {
    for (final raw in values) {
      final range = raw.split(':');
      if (range.length == 1) {
        yield _decode(raw, size);
      } else if (range.length == 2) {
        final a = _decode(range[0], size), b = _decode(range[1], size);
        if (a.row > b.row || a.col > b.col) {
          throw const FormatException('摆子范围反向');
        }
        for (var r = a.row; r <= b.row; r++) {
          for (var c = a.col; c <= b.col; c++) {
            yield Cell(r, c);
          }
        }
      } else {
        throw const FormatException('无效的摆子范围');
      }
    }
  }

  static String _coord(Cell c) =>
      '${String.fromCharCode(97 + c.col)}${String.fromCharCode(97 + c.row)}';
  static Cell _decode(String value, int size) {
    if (value.length != 2) throw FormatException('无效坐标：$value');
    final cell = Cell(value.codeUnitAt(1) - 97, value.codeUnitAt(0) - 97);
    if (cell.row < 0 || cell.col < 0 || cell.row >= size || cell.col >= size) {
      throw FormatException('坐标超出棋盘：$value');
    }
    return cell;
  }

  static String _escape(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll(']', '\\]');
  static GoRuleSet _rules(String? value) {
    final lower = (value ?? 'Chinese').toLowerCase();
    if (lower.contains('japan')) return GoRuleSet.japanese;
    if (lower.contains('korea')) return GoRuleSet.korean;
    if (lower.contains('chin')) return GoRuleSet.chinese;
    throw FormatException('暂不支持规则：$value');
  }
}

class _TreeParser {
  final String source;
  int index = 0;
  int nodes = 0;
  _TreeParser(String source) : source = source.replaceFirst('\ufeff', '');

  Never fail(String message) => throw FormatException(message, source, index);
  void whitespace() {
    while (index < source.length && source[index].trim().isEmpty) {
      index++;
    }
  }

  void expect(String ch) {
    whitespace();
    if (index >= source.length || source[index] != ch) fail('SGF 缺少 $ch');
    index++;
  }

  GoSgfNode parse() {
    if (source.length > 5000000) fail('SGF 文件过大');
    final root = tree(0);
    whitespace();
    if (index != source.length) fail('请选择仅包含一盘棋的 SGF');
    return root;
  }

  GoSgfNode tree(int depth) {
    if (depth > 128) fail('变化树层数过深');
    expect('(');
    GoSgfNode? root, tail;
    whitespace();
    while (index < source.length && source[index] == ';') {
      index++;
      if (++nodes > 50000) fail('SGF 节点过多');
      final node = GoSgfNode(properties());
      root ??= node;
      tail?.children.add(node);
      tail = node;
      whitespace();
    }
    if (root == null || tail == null) fail('SGF 树不能为空');
    while (index < source.length && source[index] == '(') {
      tail.children.add(tree(depth + 1));
      whitespace();
    }
    expect(')');
    return root;
  }

  Map<String, List<String>> properties() {
    final result = <String, List<String>>{};
    whitespace();
    while (index < source.length && !';()'.contains(source[index])) {
      final start = index;
      while (index < source.length && RegExp('[A-Z]').hasMatch(source[index])) {
        index++;
      }
      if (start == index) fail('无效属性名');
      final key = source.substring(start, index);
      if (result.containsKey(key)) fail('重复属性：$key');
      final values = <String>[];
      whitespace();
      while (index < source.length && source[index] == '[') {
        index++;
        final out = StringBuffer();
        var closed = false;
        while (index < source.length) {
          final ch = source[index++];
          if (ch == ']') {
            closed = true;
            break;
          }
          if (ch == '\\') {
            if (index >= source.length) fail('未结束的转义');
            final escaped = source[index++];
            if (escaped == '\r' || escaped == '\n') {
              if (index < source.length &&
                  (source[index] == '\r' || source[index] == '\n') &&
                  source[index] != escaped) {
                index++;
              }
            } else {
              out.write(escaped);
            }
          } else {
            out.write(ch);
          }
        }
        if (!closed) fail('未结束的属性值');
        values.add(out.toString());
        whitespace();
      }
      if (values.isEmpty) fail('属性缺少值：$key');
      result[key] = values;
    }
    return result;
  }
}
