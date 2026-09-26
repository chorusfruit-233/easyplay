import 'game_session.dart';
import 'go_sgf.dart';

/// One SGF record-tree node. The root stores game metadata/setup properties;
/// later nodes may hold a Go move, a resignation, comments, markup, or any
/// other SGF properties. Sibling nodes are alternative continuations.
class GoRecordNode {
  GoRecordNode._({
    required this.parent,
    this.move,
    this.resignedSide,
    Map<String, List<String>>? properties,
  }) : properties = properties ?? <String, List<String>>{};

  final GoRecordNode? parent;
  final GameMove? move;
  Side? resignedSide;
  final List<GoRecordNode> children = <GoRecordNode>[];
  final Map<String, List<String>> properties;

  bool get isRoot => parent == null;
  bool get isLeaf => children.isEmpty;
  bool get isVariationPoint => children.length > 1;
  GoRecordNode? get mainChild => children.isEmpty ? null : children.first;
}

/// Navigation and replay controller over an SGF-backed Go record tree.
///
/// The tree is the source of truth: [sessionForCurrent] rebuilds a fresh
/// [GameSession] from the root-to-cursor record path. Appending at a node with
/// existing continuations always creates a new sibling variation.
class GoSgfController {
  factory GoSgfController({GoConfig config = const GoConfig()}) {
    final root = _newRoot(config);
    return GoSgfController._(config, root, root);
  }

  GoSgfController._(this._config, this.root, this.current);

  final GoConfig _config;
  GoConfig get config => _config;
  GoRecordNode root;
  GoRecordNode current;

  /// Imports all SGF branches and positions the cursor at the end of the
  /// selected variation. [variation] uses child indexes at branch points,
  /// matching [GoSgf.importGame].
  factory GoSgfController.fromSgf(
    String sgf, {
    List<int> variation = const <int>[],
  }) {
    final selectedGame = GoSgf.importGame(sgf, variation: variation);
    final parsed = GoSgf.parseRecord(sgf).root;
    final root = _copyFromSgf(parsed, null);
    final choices = List<int>.of(variation);
    var choiceIndex = 0;
    var cursor = root;
    while (cursor.children.isNotEmpty) {
      var childIndex = 0;
      if (cursor.children.length > 1) {
        childIndex = choiceIndex < choices.length ? choices[choiceIndex++] : 0;
        if (childIndex < 0 || childIndex >= cursor.children.length) {
          throw const FormatException('所选 SGF 变化不存在');
        }
      }
      cursor = cursor.children[childIndex];
    }
    // SGF stores the result at the collection root. Project a resignation
    // result onto the selected line's terminal node so replay can represent
    // that terminal state without treating result metadata as a move.
    final result = root.properties['RE']?.first.toUpperCase();
    if (cursor.resignedSide == null && (result == 'B+R' || result == 'W+R')) {
      cursor.resignedSide = result == 'B+R' ? Side.white : Side.black;
    }
    return GoSgfController._(selectedGame.goConfig, root, cursor);
  }

  /// Current root-to-node path, including the root node.
  List<GoRecordNode> get path {
    final result = <GoRecordNode>[];
    for (GoRecordNode? node = current; node != null; node = node.parent) {
      result.add(node);
    }
    return List<GoRecordNode>.unmodifiable(result.reversed);
  }

  List<GoRecordNode> get leaves {
    final result = <GoRecordNode>[];
    void visit(GoRecordNode node) {
      if (node.isLeaf) {
        result.add(node);
        return;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
    return List<GoRecordNode>.unmodifiable(result);
  }

  /// Child indexes at branch points on [node]'s root-to-node path. This uses
  /// the same compact convention as [GoSgf.importGame]'s `variation` argument.
  List<int> variationChoices(GoRecordNode node) {
    if (!_belongsToTree(node)) {
      throw ArgumentError('Node belongs to another record');
    }
    final ancestors = <GoRecordNode>[];
    for (GoRecordNode? cursor = node; cursor != null; cursor = cursor.parent) {
      ancestors.add(cursor);
    }
    final ordered = ancestors.reversed.toList();
    final choices = <int>[];
    for (var i = 1; i < ordered.length; i++) {
      final parent = ordered[i - 1];
      if (parent.children.length > 1) {
        choices.add(parent.children.indexOf(ordered[i]));
      }
    }
    return List<int>.unmodifiable(choices);
  }

  /// Append an already validated move to the current node. If a matching
  /// child exists, [reuseMatchingChild] optionally follows it; otherwise a
  /// new child is appended and retained as another variation.
  GoRecordNode appendMove(
    GameMove move, {
    Map<String, List<String>>? properties,
    bool reuseMatchingChild = false,
  }) {
    if (move.from != null) {
      throw ArgumentError('Go record moves cannot have a source point');
    }
    if (move.side == null) {
      throw ArgumentError('Go record move must include side');
    }
    if (move.pass && move.to != const Cell(-1, -1)) {
      throw ArgumentError('Pass moves must use Cell(-1, -1)');
    }
    if (!move.pass &&
        (move.to.row < 0 ||
            move.to.col < 0 ||
            move.to.row >= _config.boardSize ||
            move.to.col >= _config.boardSize)) {
      throw ArgumentError('Move is outside the configured Go board');
    }
    if (reuseMatchingChild) {
      for (final child in current.children) {
        if (_sameMove(child.move, move)) {
          current = child;
          return child;
        }
      }
    }
    final props = _copyProperties(properties);
    props.remove('B');
    props.remove('W');
    props[move.side == Side.black ? 'B' : 'W'] = [
      move.pass ? '' : _encode(move.to),
    ];
    final node = GoRecordNode._(parent: current, move: move, properties: props);
    current.children.add(node);
    current = node;
    return node;
  }

  GoRecordNode appendPass({
    required Side side,
    Map<String, List<String>>? properties,
  }) => appendMove(
    GameMove(to: const Cell(-1, -1), pass: true, side: side),
    properties: properties,
  );

  /// Records resignation as SGF result metadata on the resignation node.
  /// Existing sibling branches are preserved.
  GoRecordNode appendResignation(
    Side resignedSide, {
    Map<String, List<String>>? properties,
  }) {
    final winner = resignedSide.opponent;
    final props = _copyProperties(properties);
    props['RE'] = [winner == Side.black ? 'B+R' : 'W+R'];
    final node = GoRecordNode._(
      parent: current,
      resignedSide: resignedSide,
      properties: props,
    );
    current.children.add(node);
    current = node;
    return node;
  }

  bool navigateParent() {
    final parent = current.parent;
    if (parent == null) return false;
    current = parent;
    return true;
  }

  bool navigateChild(int index) {
    if (index < 0 || index >= current.children.length) return false;
    current = current.children[index];
    return true;
  }

  bool navigateTo(GoRecordNode node) {
    if (!_belongsToTree(node)) return false;
    current = node;
    return true;
  }

  /// Move the cursor to the start of the selected line without deleting any
  /// recorded variations.
  void restartCurrentBranch() => current = root;

  /// Replay the current path into an independent, fresh game session.
  GameSession sessionForCurrent() {
    final replayRoot = _toSgfPath();
    final sgf = GoSgf.exportRecord(GoSgfRecord(replayRoot));
    final game = GoSgf.importGame(sgf);
    final resignation = current.resignedSide;
    if (resignation != null && !game.gameOver) game.resignGo(resignation);
    return game;
  }

  /// Alias that emphasizes replaying the tree cursor into a session.
  GameSession replayCurrentPath() => sessionForCurrent();

  String exportSgf() => GoSgf.exportRecord(GoSgfRecord(_toSgfTree(root)));

  GoSgfRecord exportRecord() => GoSgfRecord(_toSgfTree(root));

  bool _belongsToTree(GoRecordNode node) {
    GoRecordNode? cursor = node;
    while (cursor?.parent != null) {
      cursor = cursor!.parent;
    }
    return identical(cursor, root);
  }

  GoSgfNode _toSgfPath() {
    final nodes = path;
    final copiedRoot = _toSgfNode(nodes.first);
    var tail = copiedRoot;
    for (final node in nodes.skip(1)) {
      final child = _toSgfNode(node);
      tail.children.add(child);
      tail = child;
    }
    // RE is game-level metadata; include it only when the current path ends
    // in a resignation marker. GoSgf.importGame consumes it from the root.
    copiedRoot.properties.remove('RE');
    if (current.resignedSide case final resigned?) {
      copiedRoot.properties['RE'] = [
        resigned.opponent == Side.black ? 'B+R' : 'W+R',
      ];
      if (tail.properties.containsKey('RE')) tail.properties.remove('RE');
    }
    return copiedRoot;
  }

  static GoSgfNode _toSgfTree(GoRecordNode source) {
    final node = _toSgfNode(source);
    for (final child in source.children) {
      node.children.add(_toSgfTree(child));
    }
    return node;
  }

  static GoSgfNode _toSgfNode(GoRecordNode source) {
    final props = _copyProperties(source.properties);
    if (source.move case final move?) {
      final key = move.side == Side.black ? 'B' : 'W';
      props[key] = [move.pass ? '' : _encode(move.to)];
    }
    if (source.resignedSide case final resigned?) {
      props['RE'] = [resigned.opponent == Side.black ? 'B+R' : 'W+R'];
    }
    return GoSgfNode(props);
  }

  static GoRecordNode _copyFromSgf(GoSgfNode source, GoRecordNode? parent) {
    final props = _copyProperties(source.properties);
    GameMove? move;
    Side? resignedSide;
    final hasBlack = props.containsKey('B');
    final hasWhite = props.containsKey('W');
    if (hasBlack && hasWhite) {
      throw const FormatException('同一 SGF 节点不能同时包含黑白落子');
    }
    if (hasBlack || hasWhite) {
      final side = hasBlack ? Side.black : Side.white;
      final raw = props[hasBlack ? 'B' : 'W']!.first;
      if (raw.toLowerCase() == 'resign' || raw.toLowerCase() == 'resignation') {
        resignedSide = side;
      } else {
        final pass = raw.isEmpty || raw == 'tt';
        move = GameMove(
          to: pass ? const Cell(-1, -1) : _decode(raw),
          pass: pass,
          side: side,
        );
      }
    }
    final re = props['RE']?.first.toUpperCase();
    if (source.children.isEmpty && (re == 'B+R' || re == 'W+R')) {
      resignedSide ??= re == 'B+R' ? Side.white : Side.black;
    }
    final node = GoRecordNode._(
      parent: parent,
      move: move,
      resignedSide: resignedSide,
      properties: props,
    );
    for (final child in source.children) {
      node.children.add(_copyFromSgf(child, node));
    }
    return node;
  }

  static GoRecordNode _newRoot(GoConfig config) => GoRecordNode._(
    parent: null,
    properties: <String, List<String>>{
      'GM': ['1'],
      'FF': ['4'],
      'CA': ['UTF-8'],
      'SZ': ['${config.boardSize}'],
      'RU': [config.rules.sgfName],
      'KM': ['${config.komi}'],
      if (config.handicap > 0) 'HA': ['${config.handicap}'],
    },
  );

  static Map<String, List<String>> _copyProperties(
    Map<String, List<String>>? properties,
  ) => properties == null
      ? <String, List<String>>{}
      : properties.map((key, values) => MapEntry(key, List<String>.of(values)));

  static bool _sameMove(GameMove? left, GameMove right) =>
      left != null &&
      left.from == right.from &&
      left.to == right.to &&
      left.pass == right.pass &&
      left.side == right.side;

  static String _encode(Cell cell) =>
      '${String.fromCharCode(97 + cell.col)}${String.fromCharCode(97 + cell.row)}';

  static Cell _decode(String raw) {
    if (raw.length != 2) throw FormatException('无效 SGF 落子坐标：$raw');
    final cell = Cell(raw.codeUnitAt(1) - 97, raw.codeUnitAt(0) - 97);
    if (cell.row < 0 || cell.col < 0 || cell.row >= 52 || cell.col >= 52) {
      throw FormatException('无效 SGF 落子坐标：$raw');
    }
    return cell;
  }
}
