import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game_session.dart';
import 'go_analysis.dart';
import 'go_encoding.dart';
import 'go_file_service.dart';
import 'go_sgf.dart';
import 'go_record.dart';
import 'go_variation_tree.dart';
import 'go_storage.dart';
import 'go_ai_settings.dart';
import 'go_models.dart';
import 'go_engine_profiles.dart';
import 'go_engine_manager.dart';
import 'katago.dart';
import 'board.dart';
import 'go_placement.dart';

extension GameTypeX on GameType {
  String get label => switch (this) {
    GameType.go => '围棋',
    GameType.chess => '国际象棋',
    GameType.checkers => '跳棋',
    GameType.gomoku => '五子棋',
    GameType.xiangqi => '中国象棋',
    GameType.doudizhu => '斗地主',
  };
  String get english => switch (this) {
    GameType.go => 'GO',
    GameType.chess => 'CHESS',
    GameType.checkers => 'CHECKERS',
    GameType.gomoku => 'GOMOKU',
    GameType.xiangqi => 'XIANGQI',
    GameType.doudizhu => 'DOUDIZHU',
  };
  String get description => switch (this) {
    GameType.go => '在方寸之间，寻找全局的平衡',
    GameType.chess => '经典战略，驾驭每一步',
    GameType.checkers => '轻快对弈，跳出你的节奏',
    GameType.gomoku => '连成五子，攻守之间见胜负',
    GameType.xiangqi => '楚河汉界，运筹将帅之间',
    GameType.doudizhu => '三人纸牌，地主与农民的协作',
  };
  IconData get icon => switch (this) {
    GameType.go => Icons.blur_on,
    GameType.chess => Icons.castle,
    GameType.checkers => Icons.grid_4x4,
    GameType.gomoku => Icons.grain,
    GameType.xiangqi => Icons.account_balance,
    GameType.doudizhu => Icons.style,
  };
}

class _GoGameSetup {
  final GoConfig goConfig;
  final GoAiSettings aiSettings;
  const _GoGameSetup(this.goConfig, this.aiSettings);
}

/// Stands in for the engine in the setup dialog's dropdown when nobody is
/// playing the other colour. Not an engine id, so it can never be resolved.
const _noEngineId = '__none__';

/// What the robot panel is currently for.
///
/// A game that is already being played against the engine opens straight on
/// [play]; only a game with nothing decided yet asks which of the two it is.
enum _GoPanelMode {
  /// Two ways in: call the engine out, or review the position.
  choose,

  /// Board actions: 设置 / 分析 / 停一手 / 悔棋 / 认输.
  play,

  /// Review: run the engine's analysis and show its overlays.
  review,
}

class GamePage extends StatefulWidget {
  final GameType type;
  final GoConfig? goConfig;
  final GoAiSettings? aiSettings;
  final bool? useAndroidKataGo;

  /// Test hook: keeps board interaction available without starting the engine,
  /// which would make moves on its own and race with an assertion.
  final bool allowComputerMoves;

  /// Whether to ask for rules and opponent before the first move.
  ///
  /// The AI 对弈 entry wants that dialog; 新建棋谱 and a reopened game already
  /// know what they are and would only be asked again.
  final bool askForSetup;

  /// A stored game to reopen instead of starting from an empty board.
  final GoSavedRecord? reopen;
  const GamePage({
    super.key,
    required this.type,
    this.goConfig,
    this.aiSettings,
    this.useAndroidKataGo,
    this.allowComputerMoves = true,
    this.askForSetup = true,
    this.reopen,
  });
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late GameSession session;
  late GoSgfController _goRecord;
  late GoAiSettings aiSettings;
  bool vsComputer = true;
  GoGameKind? _recordKind;
  bool get _onlineReplay =>
      _recordKind == GoGameKind.online && !session.goScoreConfirmed;
  Side humanSide = Side.black;
  bool computerThinking = false;
  int _computerGeneration = 0;
  bool _modalOpen = false;
  bool _adjudicationInProgress = false;
  String? _activeMarkup;
  String _gameId = DateTime.now().microsecondsSinceEpoch.toString();
  final KataGoAndroidRuntime _kataGo = KataGoAndroidRuntime();
  final KataGoWebRuntime _webKataGo = KataGoWebRuntime();
  bool _engineUnavailableNotified = false;
  GoPlacementMode placementMode = GoPlacementMode.automatic;

  /// Bottom panels. Each card holds two tabs and collapses on its own, matching
  /// the reference layout: notes/AI summary above, tree/PV below.
  int _noteTab = 0;
  int _treeTab = 0;
  static const bool _noteCollapsed = false;
  static const bool _treeCollapsed = false;

  /// Analysis is a separate feature from playing a move; the panel tracks its
  /// own running state so the stop button has something to control.
  bool _analysisRunning = false;

  /// Latest engine analysis of the board, if any.
  ///
  /// Every number in it describes exactly one position, so the result is retired
  /// as soon as the session it was computed from is replaced or edited, rather
  /// than shown next to a different board.
  GoAnalysis? _analysisResult;
  GameSession? _analysisSession;
  int _analysisDeadStones = 0;
  String? _analysisError;

  GoAnalysis? get _analysis =>
      identical(_analysisSession, session) &&
          _analysisDeadStones == session.deadGoStones.length
      ? _analysisResult
      : null;

  /// Which candidate row the PV tab is showing; always a valid index while
  /// [_analysis] has moves.
  int _analysisFocus = 0;

  /// The robot button reveals this panel; it holds the AI / review choice that
  /// used to live in the state card and in the new-game dialog.
  bool _robotPanelOpen = false;

  /// What the robot panel is showing.
  _GoPanelMode _panelMode = _GoPanelMode.choose;

  /// Review overlays drawn on the board.
  bool _showMoveHints = false;
  bool _showOwnership = false;

  /// True when the two record cards are merged into one card with four tabs.
  bool _cardsMerged = false;
  int _mergedTab = 1;

  /// Whether the engine is expected to answer for the other colour.
  ///
  /// `allowComputerMoves: false` means no engine is consulted, so neither the
  /// turn gate nor the scheduler may treat one colour as the engine's.
  bool get _computerPlays =>
      !_onlineReplay &&
      widget.allowComputerMoves &&
      vsComputer &&
      aiSettings.opponentMode == GoOpponentMode.kataGo;

  bool get _canPlay =>
      !_onlineReplay &&
      !_modalOpen &&
      !session.gameOver &&
      !computerThinking &&
      (!_computerPlays || session.turn == humanSide);

  bool get _usesKataGo => aiSettings.opponentMode == GoOpponentMode.kataGo;

  bool get _androidKataGoSupported =>
      widget.useAndroidKataGo ?? KataGoAndroidRuntime.isSupported;

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _fallbackToLocalMode(String reason) {
    _computerGeneration++;
    if (!mounted) return;
    setState(() {
      vsComputer = false;
      computerThinking = false;
      aiSettings = aiSettings.copyWith(opponentMode: GoOpponentMode.local);
    });
    _notice('内置引擎不可用，已切换为本地双人模式：$reason');
    _persistGo();
  }

  void _pauseComputer() {
    _computerGeneration++;
    setState(() {
      computerThinking = false;
      _modalOpen = true;
      _adjudicationInProgress = false;
    });
  }

  @override
  void dispose() {
    _computerGeneration++;
    _kataGo.stop();
    super.dispose();
  }

  Cell? selected;
  List<Cell> targets = const [];

  @override
  void initState() {
    super.initState();
    session = GameSession(widget.type, goConfig: widget.goConfig);
    _goRecord = _newRecordForSession(session);
    aiSettings = widget.aiSettings ?? const GoAiSettings();
    vsComputer = aiSettings.opponentMode != GoOpponentMode.local;
    // A game with an engine opens on the board actions; a bare record has to be
    // asked what it is for first.
    _panelMode = vsComputer ? _GoPanelMode.play : _GoPanelMode.choose;
    humanSide = aiSettings.resolvePlayerSide();
    GoPlacementPreferences.load().then((value) {
      if (mounted) setState(() => placementMode = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.type != GameType.go) return;
      final saved = widget.reopen;
      if (saved != null) {
        _openSavedGame(saved);
        return;
      }
      if (widget.askForSetup) _showGoSettings(requiredAtStart: true);
    });
  }

  /// Reopens a stored game: position, opponent and player colour together, so a
  /// game continued from the Go home page picks up where it stopped.
  void _openSavedGame(GoSavedRecord saved) {
    try {
      final record = GoSgfController.fromSgf(saved.sgf);
      _replaceGo(
        record.replayCurrentPath(),
        record: record,
        id: saved.id.isEmpty ? null : saved.id,
        computer: saved.vsComputer,
        kind: saved.kind,
        settings: saved.aiSettings,
        restoredHumanSide: saved.humanSide,
      );
    } catch (error) {
      _notice('棋谱载入失败：$error');
    }
  }

  GoSgfController _newRecordForSession(GameSession game) {
    final record = GoSgfController(config: game.goConfig);
    final black = <String>[];
    final white = <String>[];
    for (var row = 0; row < game.size; row++) {
      for (var col = 0; col < game.size; col++) {
        final stone = game.initialGoBoard[row][col];
        if (stone == null) continue;
        (stone.side == Side.black ? black : white).add(
          _sgfCoordinate(Cell(row, col)),
        );
      }
    }
    if (black.isNotEmpty) record.root.properties['AB'] = black;
    if (white.isNotEmpty) record.root.properties['AW'] = white;
    record.root.properties['PL'] = [
      game.initialGoTurn == Side.black ? 'B' : 'W',
    ];
    return record;
  }

  void _previewGoCell(Cell cell) {
    if (widget.type != GameType.go || !_canPlay || _activeMarkup != null) {
      return;
    }
    if (!session.isLegalGoMove(cell)) return;
    setState(() => selected = cell);
  }

  void _cancelGoPreview() {
    if (widget.type != GameType.go) return;
    if (selected != null) setState(() => selected = null);
  }

  void _onCell(Cell cell) {
    if (_onlineReplay) return;
    if (_modalOpen || _adjudicationInProgress) return;
    if (widget.type == GameType.go && _activeMarkup != null) {
      final markup = _activeMarkup!;
      final coordinates = _goRecord.current.properties[markup] ?? <String>[];
      final coordinate = _sgfCoordinate(cell);
      if (markup == 'LB') {
        _editLabelAt(cell);
      } else {
        setState(() {
          final updated = List<String>.of(coordinates);
          if (updated.contains(coordinate)) {
            updated.remove(coordinate);
          } else {
            updated.add(coordinate);
          }
          _goRecord.setCurrentProperty(markup, updated);
          _activeMarkup = null;
        });
        _persistGo();
      }
      return;
    }
    if (session.gameOver && widget.type == GameType.go) {
      setState(() => session.toggleDeadGoStone(cell));
      _persistGo();
      return;
    }
    if (!_canPlay) return;
    if (widget.type == GameType.go) {
      final candidate = _goRecord.replayCurrentPath();
      if (!candidate.placeGo(cell)) return;
      _goRecord.appendMove(candidate.moves.last);
      setState(() {
        session = _goRecord.replayCurrentPath();
        selected = null;
        targets = const [];
      });
      _persistGo();
      // Keep the engine and the record cursor in lockstep before asking for
      // the reply. This also prevents a stale search from using the previous
      // branch when a human move was appended at a historical node.
      _recordMoveForEngine(
        session.moves.last,
      ).whenComplete(_scheduleComputerMove);
      return;
    }
    final before = session.moves.length;
    setState(() {
      if (widget.type == GameType.go) {
        session.placeGo(cell);
        selected = null;
        targets = const [];
      }
    });
    if (session.moves.length != before) _persistGo();
    if (widget.type == GameType.go && session.moves.length != before) {
      _recordMoveForEngine(session.moves.last);
    }
    _scheduleComputerMove();
  }

  Future<void> _editComment() async {
    final controller = TextEditingController(
      text: _goRecord.current.properties['C']?.firstOrNull ?? '',
    );
    final comment = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑节点注释'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(hintText: '输入注释...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (comment == null || !mounted) return;
    setState(() {
      _goRecord.setCurrentProperty(
        'C',
        comment.trim().isEmpty ? null : [comment.trim()],
      );
    });
    await _persistGo();
  }

  Future<void> _editLabelAt(Cell cell) async {
    final coordinate = _sgfCoordinate(cell);
    final values = List<String>.of(
      _goRecord.current.properties['LB'] ?? const <String>[],
    );
    final old = values
        .where((value) => value.startsWith('$coordinate:'))
        .firstOrNull;
    final controller = TextEditingController(text: old?.substring(3) ?? '');
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文字标记'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 8,
          decoration: const InputDecoration(hintText: '输入文字；留空移除标记'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (label == null || !mounted) return;
    values.removeWhere((value) => value.startsWith('$coordinate:'));
    if (label.trim().isNotEmpty) values.add('$coordinate:${label.trim()}');
    setState(() {
      _goRecord.setCurrentProperty('LB', values);
      _activeMarkup = null;
    });
    await _persistGo();
  }

  Future<void> _chooseRecordTool() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.comment_outlined),
              title: const Text('编辑注释'),
              onTap: () => Navigator.pop(context, 'comment'),
            ),
            for (final entry in const [
              ('TR', '三角标记', Icons.change_history_outlined),
              ('SQ', '方形标记', Icons.crop_square_outlined),
              ('CR', '圆形标记', Icons.circle_outlined),
              ('LB', '文字标记', Icons.label_outline),
            ])
              ListTile(
                leading: Icon(entry.$3),
                title: Text(entry.$2),
                onTap: () => Navigator.pop(context, entry.$1),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除当前节点…'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'comment':
        await _editComment();
      case 'delete':
        await _deleteCurrentNode();
      default:
        setState(() => _activeMarkup = action);
        _notice(
          '点击棋盘交叉点添加${switch (action) {
            'TR' => '三角',
            'SQ' => '方形',
            'CR' => '圆形',
            _ => '文字',
          }}标记；再打开工具可取消。',
        );
    }
  }

  Future<void> _deleteCurrentNode() async {
    if (_goRecord.current.isRoot) {
      _notice('棋谱起点不能删除');
      return;
    }
    final preserveChildren = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除当前节点'),
        content: const Text('是否保留当前节点的后续着手并提升到上一级？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('删除节点及其后续变化'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保留后续着手'),
          ),
        ],
      ),
    );
    if (preserveChildren == null || !mounted) return;
    _computerGeneration++;
    await _kataGo.stop();
    if (!mounted) return;
    setState(() {
      _goRecord.deleteCurrent(preserveChildren: preserveChildren);
      session = _goRecord.replayCurrentPath();
      _activeMarkup = null;
      selected = null;
      targets = const [];
      computerThinking = false;
    });
    await _persistGo();
    _scheduleComputerMove();
  }

  Future<void> _showSgfText() async {
    final text = _persistedRecordSgf();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SGF 内容'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) Navigator.pop(context);
              _notice('SGF 内容已复制');
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordMoveForEngine(GameMove move) async {
    if (!_usesKataGo || !_kataGo.isStarted) return;
    final generation = _computerGeneration;
    try {
      await _kataGo.send(
        'play ${move.side == Side.black ? 'B' : 'W'} ${_gtpVertex(move)}',
      );
    } catch (error) {
      if (!mounted || generation != _computerGeneration || !_usesKataGo) {
        return;
      }
      try {
        await _kataGo.stop();
      } catch (_) {
        // Keep the game usable even when the native process is already gone.
      }
      _engineUnavailableNotified = true;
      _fallbackToLocalMode('局面同步失败：$error');
    }
  }

  String _gtpVertex(GameMove move) {
    if (move.pass) return 'pass';
    const letters = 'ABCDEFGHJKLMNOPQRST';
    return '${letters[move.to.col]}${session.size - move.to.row}';
  }

  Future<void> _startKataGoAndReplay() async {
    if (_onlineReplay) return;
    await _kataGo.start(config: session.goConfig, settings: aiSettings);
    for (final command in _gtpSetupCommands()) {
      await _kataGo.send(command);
    }
    for (final move in session.moves) {
      await _kataGo.send(
        'play ${move.side == Side.black ? 'B' : 'W'} ${_gtpVertex(move)}',
      );
    }
  }

  List<String> _gtpSetupCommands() {
    final stones = <String>[];
    var blackCount = 0;
    var onlyBlack = true;
    for (var row = 0; row < session.size; row++) {
      for (var col = 0; col < session.size; col++) {
        final stone = session.initialGoBoard[row][col];
        if (stone == null) continue;
        if (stone.side == Side.black) blackCount++;
        if (stone.side != Side.black) onlyBlack = false;
        stones.add(
          '${stone.side == Side.black ? 'B' : 'W'} ${_gtpVertex(GameMove(to: Cell(row, col)))}',
        );
      }
    }
    if (stones.isEmpty) return const [];
    if (onlyBlack && blackCount >= 2 && blackCount <= 9) {
      return [
        'set_free_handicap ${stones.map((s) => s.split(' ').last).join(' ')}',
      ];
    }
    return [
      'set_position ${stones.join(' ')}',
      if (session.initialGoTurn == Side.white) 'play B pass',
    ];
  }

  Future<void> _persistGo() async {
    if (widget.type != GameType.go) return;
    try {
      await GoStorage.saveLast(
        _persistedRecordSgf(),
        gameId: _gameId,
        vsComputer: vsComputer,
        kind: _recordKind == GoGameKind.online ? GoGameKind.online : null,
        aiSettings: aiSettings,
        humanSide: humanSide,
      );
    } catch (e) {
      _notice('棋局未保存，请导出 SGF 备份：$e');
    }
  }

  String _persistedRecordSgf() {
    if (widget.type != GameType.go) return '';
    final currentProperties = _goRecord.current.properties;
    if (session.deadGoStones.isEmpty) {
      currentProperties.remove('XDS');
    } else {
      currentProperties['XDS'] = session.deadGoStones
          .map(_sgfCoordinate)
          .toList();
    }
    if (session.goScoreConfirmed) {
      currentProperties['XSC'] = ['1'];
      final score = session.calculateGoScore();
      _goRecord.root.properties['RE'] = [
        score.winner == null
            ? '0'
            : '${score.winner == Side.black ? 'B' : 'W'}+${score.resignation ? 'R' : score.margin}',
      ];
    } else {
      currentProperties.remove('XSC');
      if (session.goResignedSide == null) {
        final result = _goRecord.root.properties['RE']?.first.toUpperCase();
        if (result != 'B+R' && result != 'W+R') {
          _goRecord.root.properties.remove('RE');
        }
      }
    }
    return _goRecord.exportSgf();
  }

  String _sgfCoordinate(Cell cell) =>
      '${String.fromCharCode(97 + cell.col)}${String.fromCharCode(97 + cell.row)}';

  void _scheduleComputerMove() {
    if (!mounted ||
        _onlineReplay ||
        _modalOpen ||
        !_computerPlays ||
        session.gameOver ||
        session.turn == humanSide ||
        computerThinking) {
      return;
    }
    final generation = ++_computerGeneration;
    setState(() => computerThinking = true);
    Future<void>.delayed(const Duration(milliseconds: 300), () async {
      if (!mounted ||
          generation != _computerGeneration ||
          !vsComputer ||
          session.gameOver ||
          _modalOpen ||
          session.turn == humanSide) {
        return;
      }
      var played = false;
      final recordNodeBeforeSearch = _goRecord.current;
      if (widget.type == GameType.go &&
          _usesKataGo &&
          _androidKataGoSupported) {
        try {
          if (!_kataGo.isStarted) await _startKataGoAndReplay();
          if (!mounted ||
              generation != _computerGeneration ||
              !identical(recordNodeBeforeSearch, _goRecord.current)) {
            return;
          }
          final vertex = (await _kataGo.send(
            'genmove ${session.turn == Side.black ? 'B' : 'W'}',
          )).trim();
          if (!mounted ||
              generation != _computerGeneration ||
              !identical(recordNodeBeforeSearch, _goRecord.current)) {
            return;
          }
          played = _playGtpVertex(vertex);
          if (!played) throw StateError('KataGo 返回了非法着手：$vertex');
        } catch (error) {
          if (!_engineUnavailableNotified) {
            _engineUnavailableNotified = true;
            _fallbackToLocalMode('引擎启动失败：$error');
          }
          try {
            await _kataGo.stop();
          } catch (_) {
            // The platform channel may be unavailable in tests or partial hosts.
          }
        }
      } else if (widget.type == GameType.go &&
          _usesKataGo &&
          KataGoWebRuntime.isSupported) {
        try {
          final setup = _gtpSetupCommands();
          final vertex = (await _webKataGo.genmove(
            config: session.goConfig,
            settings: aiSettings,
            setup: setup,
            moves: session.moves.map(_gtpCommand).toList(),
            side: session.turn,
          )).trim();
          if (!mounted ||
              generation != _computerGeneration ||
              !identical(recordNodeBeforeSearch, _goRecord.current)) {
            return;
          }
          played = _playGtpVertex(vertex);
          if (!played) throw StateError('KataGo 返回了非法着手：$vertex');
        } catch (error) {
          if (!_engineUnavailableNotified) {
            _engineUnavailableNotified = true;
            _fallbackToLocalMode('Web 引擎启动失败：$error');
          }
        }
      }
      if (!played && mounted && generation == _computerGeneration) {
        _fallbackToLocalMode('当前平台没有可用的 KataGo 引擎');
      } else if (mounted && generation == _computerGeneration) {
        setState(() => computerThinking = false);
      }
      _persistGo();
      if (session.gameOver && widget.type == GameType.go) {
        await _autoAdjudicate(generation);
      }
    });
  }

  Cell _cellFromGtp(String vertex) {
    const letters = 'ABCDEFGHJKLMNOPQRST';
    if (vertex.length < 2) throw FormatException('无效 KataGo 坐标：$vertex');
    final col = letters.indexOf(vertex[0].toUpperCase());
    final rowNumber = int.tryParse(vertex.substring(1));
    if (col < 0 || rowNumber == null) {
      throw FormatException('无效 KataGo 坐标：$vertex');
    }
    return Cell(session.size - rowNumber, col);
  }

  bool _playGtpVertex(String vertex) {
    if (widget.type != GameType.go) return false;
    final candidate = _goRecord.replayCurrentPath();
    final ok = vertex.toLowerCase() == 'pass'
        ? candidate.passGo()
        : vertex.toLowerCase() == 'resign'
        ? candidate.resignGo()
        : candidate.placeGo(_cellFromGtp(vertex));
    if (!ok) return false;
    if (vertex.toLowerCase() == 'resign') {
      _goRecord.appendResignation(candidate.goResignedSide ?? candidate.turn);
    } else {
      _goRecord.appendMove(candidate.moves.last);
    }
    session = _goRecord.replayCurrentPath();
    return true;
  }

  String _gtpCommand(GameMove move) =>
      'play ${move.side == Side.black ? 'B' : 'W'} ${_gtpVertex(move)}';

  Future<void> _undo() async {
    _computerGeneration++;
    final undoCount =
        vsComputer && session.turn == humanSide && session.moves.length >= 2
        ? 2
        : 1;
    setState(() {
      computerThinking = false;
      _adjudicationInProgress = false;
      selected = null;
      targets = const [];
      if (widget.type == GameType.go) {
        for (var i = 0; i < undoCount; i++) {
          _goRecord.navigateParent();
        }
        session = _goRecord.replayCurrentPath();
      } else if (undoCount == 2) {
        session.undo();
        session.undo();
      } else {
        session.undo();
      }
    });
    // Rebuild the engine from the selected SGF path on its next turn. A GTP
    // undo count cannot represent setup nodes, resignation nodes or branches.
    await _kataGo.stop();
    _persistGo();
    _scheduleComputerMove();
  }

  Future<void> _restart() async {
    final generation = ++_computerGeneration;
    setState(() {
      _recordKind = null;
      _gameId = DateTime.now().microsecondsSinceEpoch.toString();
      if (widget.type == GameType.go) {
        _goRecord = _newRecordForSession(
          GameSession(GameType.go, goConfig: session.goConfig),
        );
        session = _goRecord.replayCurrentPath();
      } else {
        session.reset();
      }
      selected = null;
      targets = const [];
      computerThinking = false;
      _adjudicationInProgress = false;
      // A fresh board with the same opponent has nothing chosen for it yet.
      _panelMode = vsComputer ? _GoPanelMode.play : _GoPanelMode.choose;
    });
    try {
      await _kataGo.stop();
    } catch (_) {
      // A reset must remain usable if a previous native search already failed.
    }
    if (!mounted || generation != _computerGeneration) return;
    _persistGo();
    _scheduleComputerMove();
  }

  Future<void> _pass() async {
    if (!_canPlay) return;
    final candidate = _goRecord.replayCurrentPath();
    if (!candidate.passGo()) return;
    _goRecord.appendMove(candidate.moves.last);
    setState(() => session = _goRecord.replayCurrentPath());
    if (session.moves.isNotEmpty) {
      await _recordMoveForEngine(session.moves.last);
    }
    _persistGo();
    if (session.gameOver) {
      await _autoAdjudicate(_computerGeneration);
    } else {
      _scheduleComputerMove();
    }
  }

  /// Ends the game as a resignation.
  ///
  /// Resigning is destructive and irreversible, so it asks first; an accidental
  /// tap here would otherwise throw away the game.
  Future<void> _resign() async {
    if (widget.type != GameType.go || session.gameOver) return;
    _pauseComputer();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认认输？'),
        content: Text(
          vsComputer
              ? '本局将判${humanSide.opponent.label}胜。'
              : '本局将判${session.turn.opponent.label}胜。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('认输'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _modalOpen = false);
    if (confirmed != true) {
      _scheduleComputerMove();
      return;
    }
    // With an engine in the game the human is the one giving up; a record can
    // resign for whoever is to move.
    final side = vsComputer ? humanSide : session.turn;
    final candidate = _goRecord.replayCurrentPath();
    if (!candidate.resignGo(side)) {
      _scheduleComputerMove();
      return;
    }
    _goRecord.appendResignation(side);
    setState(() {
      session = _goRecord.replayCurrentPath();
      selected = null;
      targets = const [];
      computerThinking = false;
      _adjudicationInProgress = false;
    });
    _persistGo();
  }

  Future<void> _continueGo() async {
    if (widget.type != GameType.go || !session.gameOver) return;
    _computerGeneration++;
    // A double pass is a terminal branch. Continuing means returning to the
    // first pass node and leaving the second pass as an intact sibling; the
    // next move appended by the user therefore becomes a new SGF variation.
    if (_goRecord.current.move?.pass == true &&
        _goRecord.current.parent?.move?.pass == true) {
      _goRecord.navigateParent();
    } else if (_goRecord.current.parent != null) {
      _goRecord.navigateParent();
    }
    await _kataGo.stop();
    if (!mounted) return;
    setState(() {
      session = _goRecord.replayCurrentPath();
      selected = null;
      targets = const [];
      computerThinking = false;
      _adjudicationInProgress = false;
    });
    await _persistGo();
    _scheduleComputerMove();
  }

  Future<void> _autoAdjudicate(int generation) async {
    if (_onlineReplay) return;
    if (_adjudicationInProgress || !session.gameOver || !mounted) return;
    final recordNodeBeforeAdjudication = _goRecord.current;
    setState(() => _adjudicationInProgress = true);
    try {
      final setup = _gtpSetupCommands();
      final moves = session.moves.map(_gtpCommand).toList();
      late final String deadResponse;
      late final String scoreResponse;
      if (_androidKataGoSupported) {
        if (!_kataGo.isStarted) await _startKataGoAndReplay();
        deadResponse = await _kataGo.send('final_status_list dead');
        scoreResponse = await _kataGo.send('final_score');
      } else if (KataGoWebRuntime.isSupported) {
        final result = await _webKataGo.adjudicate(
          config: session.goConfig,
          settings: aiSettings,
          setup: setup,
          moves: moves,
        );
        deadResponse = result['dead'] as String? ?? '';
        scoreResponse = result['score'] as String? ?? '';
      } else {
        throw UnsupportedError('当前平台没有可用的 KataGo 终局裁定引擎');
      }
      if (!mounted) return;
      if (generation != _computerGeneration ||
          !identical(recordNodeBeforeAdjudication, _goRecord.current)) {
        setState(() => _adjudicationInProgress = false);
        return;
      }
      final dead = <Cell>{};
      for (final vertex in deadResponse.split(RegExp(r'\s+'))) {
        if (vertex.trim().isEmpty) continue;
        dead.add(_cellFromGtp(vertex.trim()));
      }
      final result = RegExp(
        r'^([BW])\+([0-9]+(?:\.[0-9]+)?)$',
      ).firstMatch(scoreResponse.trim());
      final adjudicatedWinner = result == null
          ? null
          : (result.group(1) == 'B' ? Side.black : Side.white);
      final margin = result == null ? 0.0 : double.parse(result.group(2)!);
      setState(() {
        session.adjudicateGo(
          dead,
          adjudicatedWinner: adjudicatedWinner,
          margin: margin,
        );
        _adjudicationInProgress = false;
      });
      _persistGo();
    } catch (error) {
      if (!mounted) return;
      if (generation != _computerGeneration ||
          !identical(recordNodeBeforeAdjudication, _goRecord.current)) {
        setState(() => _adjudicationInProgress = false);
        return;
      }
      setState(() => _adjudicationInProgress = false);
      _notice('自动死活裁定失败，请双方核对死子后手动确认：$error');
    }
  }

  Widget _setupField(String label, Widget field) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        field,
      ],
    ),
  );

  Future<void> _showGoSettings({
    bool requiredAtStart = false,
    bool preferEngine = false,
  }) async {
    if (widget.type != GameType.go || _onlineReplay) return;
    if (requiredAtStart) {
      _computerGeneration++;
      setState(() {
        computerThinking = false;
        _modalOpen = true;
      });
    } else {
      _pauseComputer();
    }
    final formKey = GlobalKey<FormState>();
    var size = session.goConfig.boardSize;
    var rules = session.goConfig.rules;
    final komiController = TextEditingController(
      text: session.goConfig.komi.toString(),
    );
    var komiEdited = false;
    var handicap = session.goConfig.handicap;
    var mode = preferEngine && aiSettings.opponentMode == GoOpponentMode.local
        ? GoOpponentMode.kataGo
        : aiSettings.opponentMode;
    var playerColor = aiSettings.playerColor;
    var rank = aiSettings.rank;
    var style = aiSettings.style;
    var humanModelId = aiSettings.humanModelId;
    var humanRank = aiSettings.resolvedHumanStyleRank;
    final humanProfile = TextEditingController(
      text: aiSettings.humanSLProfile ?? '',
    );
    // The engine profile is the single source of truth for which networks to
    // load; there is no separately selectable "current model".
    var availableModels = <GoModelInfo>[GoModelLibrary.bundledModel];
    var engines = <GoEngineProfile>[GoEngineProfile.builtIn];
    var activeEngine = GoEngineProfile.builtIn.id;
    try {
      availableModels = await GoModelLibrary.available();
      engines = await GoEngineLibrary.available();
      activeEngine = await GoEngineLibrary.activeId();
    } catch (error) {
      _notice('读取 KataGo 模型列表失败，暂用内置 b6 模型：$error');
    }
    var modelId = kIsWeb ? GoModelLibrary.bundledId : GoModelLibrary.bundledId;
    var engineProfileId = requiredAtStart && widget.aiSettings == null
        ? activeEngine
        : engines.any((engine) => engine.id == aiSettings.engineProfileId)
        ? aiSettings.engineProfileId
        : activeEngine;

    /// Ranks the loaded main model can actually back. The bundled b6 is a small
    /// v8 network, so it stops at 5d instead of offering labels it cannot reach.
    List<GoAiRank> selectableRanks() {
      final model = availableModels.where((m) => m.id == modelId).firstOrNull;
      final bundled = model == null || model.bundled;
      final highest = bundled ? -4 : -8;
      final ranks = GoAiRank.availableFor(highestHumanRank: highest);
      return ranks.isEmpty ? GoAiRank.values : ranks;
    }

    void applyEngineSelection() {
      final selected = engines.firstWhere((e) => e.id == engineProfileId);
      if (!kIsWeb && availableModels.any((m) => m.id == selected.modelId)) {
        modelId = selected.modelId!;
      }
      humanModelId =
          availableModels.any(
            (m) => m.id == selected.humanModelId && m.isHumanModel,
          )
          ? selected.humanModelId
          : null;
      if (humanModelId != null) {
        style = GoAiStyle.human;
      } else if (style == GoAiStyle.human) {
        style = GoAiStyle.modern;
      }
    }

    if (requiredAtStart && widget.aiSettings == null) {
      applyEngineSelection();
    }
    if (humanModelId != null &&
        !availableModels.any((m) => m.id == humanModelId && m.isHumanModel)) {
      humanModelId = null;
    }
    if (!mounted) return;
    var starting = false;
    String? setupError;
    final result = await showDialog<_GoGameSetup>(
      context: context,
      barrierDismissible: !starting,
      builder: (context) => PopScope(
        canPop: !starting,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            title: Text(requiredAtStart ? '新建 AI 对局' : 'AI 设置'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 2,
                  children: [
                    _setupField(
                      '棋盘路数',
                      DropdownButtonFormField<int>(
                        initialValue: size,
                        decoration: const InputDecoration(),
                        items: [9, 13, 19]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text('$v×$v'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => size = v ?? size),
                      ),
                    ),
                    _setupField(
                      '计分规则',
                      DropdownButtonFormField<GoRuleSet>(
                        key: ValueKey(rules),
                        initialValue: rules,
                        decoration: const InputDecoration(),
                        items: GoRuleSet.values
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setDialogState(() {
                          rules = v ?? rules;
                          if (!komiEdited) {
                            komiController.text = rules == GoRuleSet.chinese
                                ? '7.5'
                                : '6.5';
                          }
                        }),
                      ),
                    ),
                    _setupField(
                      '贴目',
                      TextFormField(
                        controller: komiController,
                        decoration: const InputDecoration(),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          return n == null || !n.isFinite || n < -100 || n > 100
                              ? '请输入 -100 至 100 的贴目'
                              : null;
                        },
                        onChanged: (_) => komiEdited = true,
                      ),
                    ),
                    _setupField(
                      '让子（黑方）',
                      DropdownButtonFormField<int>(
                        initialValue: handicap,
                        decoration: const InputDecoration(),
                        items: [0, 2, 3, 4, 5, 6, 7, 8, 9]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v == 0 ? '分先' : '$v 子'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => handicap = v ?? handicap),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // The engine choice doubles as "is anyone playing the other
                    // colour": 新建棋谱 opens with nobody, and this is where a
                    // record hands the board over to the engine.
                    _setupField(
                      '引擎',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('$mode/$engineProfileId'),
                        initialValue: mode == GoOpponentMode.local
                            ? _noEngineId
                            : engineProfileId,
                        decoration: const InputDecoration(),
                        items: [
                          const DropdownMenuItem(
                            value: _noEngineId,
                            child: Text('不下棋（仅记录）'),
                          ),
                          for (final engine in engines)
                            DropdownMenuItem(
                              value: engine.id,
                              child: Text(engine.name),
                            ),
                        ],
                        onChanged: (value) => setDialogState(() {
                          if (value == _noEngineId) {
                            mode = GoOpponentMode.local;
                            return;
                          }
                          mode = GoOpponentMode.kataGo;
                          engineProfileId = value ?? engineProfileId;
                          applyEngineSelection();
                        }),
                      ),
                    ),
                    if (mode != GoOpponentMode.local)
                      Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        spacing: 4,
                        children: [
                          for (final option in const [
                            (GoPlayerColor.black, '我执黑'),
                            (GoPlayerColor.white, '我执白'),
                            (GoPlayerColor.random, '猜先'),
                          ])
                            ChoiceChip(
                              label: Text(option.$2),
                              selected: playerColor == option.$1,
                              onSelected: (_) =>
                                  setDialogState(() => playerColor = option.$1),
                            ),
                        ],
                      ),
                    if (mode == GoOpponentMode.kataGo) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: '管理 AI 引擎',
                              onPressed: () async {
                                try {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const GoEngineManagerPage(),
                                    ),
                                  );
                                  final profiles =
                                      await GoEngineLibrary.available();
                                  final active =
                                      await GoEngineLibrary.activeId();
                                  if (!context.mounted) return;
                                  setDialogState(() {
                                    engines = profiles;
                                    engineProfileId = active;
                                    applyEngineSelection();
                                  });
                                } catch (error) {
                                  if (context.mounted) {
                                    setDialogState(
                                      () => setupError = '读取引擎配置失败：$error',
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.tune),
                            ),
                          ),
                        ],
                      ),
                      if (style != GoAiStyle.human)
                        _setupField(
                          '棋力',
                          DropdownButtonFormField<GoAiRank>(
                            initialValue: rank,
                            decoration: const InputDecoration(),
                            items: selectableRanks()
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setDialogState(() => rank = value ?? rank),
                          ),
                        ),
                      // Style is a property of the engine, not of a game: it only
                      // appears once the engine binds a human-style network, and
                      // then human style is the only possibility.
                      if (humanModelId != null)
                        _setupField(
                          '风格',
                          DropdownButtonFormField<GoAiStyle>(
                            key: ValueKey(style),
                            initialValue: style,
                            decoration: const InputDecoration(),
                            items: const [
                              DropdownMenuItem(
                                value: GoAiStyle.human,
                                child: Text('人类棋风'),
                              ),
                            ],
                            onChanged: (value) =>
                                setDialogState(() => style = value ?? style),
                          ),
                        ),
                      if (style == GoAiStyle.human) ...[
                        _setupField(
                          '人类棋风段位',
                          DropdownButtonFormField<int>(
                            initialValue: humanRank,
                            items: [
                              for (var n = 20; n >= -8; n--)
                                DropdownMenuItem(
                                  value: n,
                                  child: Text(GoAiSettings.humanRankLabel(n)),
                                ),
                            ],
                            onChanged: (v) => setDialogState(
                              () => humanRank = v ?? humanRank,
                            ),
                          ),
                        ),
                        _setupField(
                          '自定义 humanSLProfile（可选）',
                          TextFormField(
                            controller: humanProfile,
                            decoration: const InputDecoration(
                              hintText: '留空按段位生成，例如 rank_5k；传统棋风可填 preaz_5k',
                            ),
                          ),
                        ),
                      ],
                      if (setupError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            setupError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: starting ? null : () => Navigator.pop(context),
                child: Text(requiredAtStart ? '返回主页' : '取消'),
              ),
              FilledButton(
                onPressed: starting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        if (mode == GoOpponentMode.kataGo) {
                          setDialogState(() {
                            starting = true;
                            setupError = null;
                          });
                          try {
                            await GoModelLibrary.validateAvailable(modelId);
                            final selectedModel = await GoModelLibrary.byId(
                              modelId,
                            );
                            final selectedEngine = await GoEngineLibrary.byId(
                              engineProfileId,
                            );
                            final human =
                                style != GoAiStyle.human || humanModelId == null
                                ? null
                                : await GoModelLibrary.byId(humanModelId!);
                            final checkedSettings = GoAiSettings(
                              style: style,
                              humanModelId: human?.id,
                              humanStyleRank: humanRank,
                              humanSLProfile: humanProfile.text.trim().isEmpty
                                  ? null
                                  : humanProfile.text.trim(),
                            );
                            checkedSettings.validateHumanStyle();
                            if (human != null) {
                              await GoModelLibrary.validateAvailable(human.id);
                            }
                            GoModelCompatibility.validate(
                              model: selectedModel,
                              engine: selectedEngine,
                              humanModel: human,
                            );
                            if (selectedModel.isHumanModel) {
                              throw StateError('人类棋风网络只能作为人类棋风模型，不能作为主模型');
                            }
                            if (style == GoAiStyle.human && human == null) {
                              throw StateError('人类棋风模式需要在引擎里配置人类棋风模型');
                            }
                          } catch (error) {
                            if (!context.mounted) return;
                            setDialogState(() {
                              starting = false;
                              setupError = '模型不可用：$error';
                            });
                            return;
                          }
                        }
                        if (!context.mounted) return;
                        Navigator.pop(
                          context,
                          _GoGameSetup(
                            GoConfig(
                              boardSize: size,
                              rules: rules,
                              komi: double.parse(komiController.text),
                              handicap: handicap,
                            ),
                            GoAiSettings(
                              opponentMode: mode,
                              playerColor: playerColor,
                              rank: rank,
                              style: style,
                              modelId: modelId,
                              engineProfileId: engineProfileId,
                              humanModelId: style == GoAiStyle.human
                                  ? humanModelId
                                  : null,
                              humanStyleRank: humanRank,
                              humanSLProfile: humanProfile.text.trim().isEmpty
                                  ? null
                                  : humanProfile.text.trim(),
                            ),
                          ),
                        );
                      },
                child: starting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(requiredAtStart ? '开始对局' : '保存'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _modalOpen = false);
    if (result == null && requiredAtStart) {
      await _kataGo.stop();
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (result != null) {
      await _kataGo.stop();
      if (!mounted) return;
      // Board size, rules, komi and handicap are baked into the position that
      // has already been played out, so changing one has to start a new game.
      // The opponent can be swapped mid-game, which is what 设置 is usually for.
      final current = session.goConfig;
      final next = result.goConfig;
      final shapeChanged =
          current.boardSize != next.boardSize ||
          current.rules != next.rules ||
          current.komi != next.komi ||
          current.handicap != next.handicap;
      if (!requiredAtStart && !shapeChanged) {
        final hadOpponent = vsComputer;
        setState(() {
          aiSettings = result.aiSettings;
          vsComputer = aiSettings.opponentMode != GoOpponentMode.local;
          // Only follow the engine in or out of the game; leaving the panel
          // where it was avoids a jump when nothing about the opponent changed.
          if (hadOpponent != vsComputer) {
            _panelMode = vsComputer ? _GoPanelMode.play : _GoPanelMode.choose;
          }
          humanSide = aiSettings.resolvePlayerSide();
          _engineUnavailableNotified = false;
          // The engine is about to be different, so nothing it said still holds.
          _analysisResult = null;
          _analysisSession = null;
          computerThinking = false;
          _adjudicationInProgress = false;
        });
        _persistGo();
        _scheduleComputerMove();
        return;
      }
      setState(() {
        _recordKind = null;
        _gameId = DateTime.now().microsecondsSinceEpoch.toString();
        session = GameSession(GameType.go, goConfig: result.goConfig);
        _goRecord = _newRecordForSession(session);
        aiSettings = result.aiSettings;
        vsComputer = aiSettings.opponentMode != GoOpponentMode.local;
        _engineUnavailableNotified = false;
        humanSide = aiSettings.resolvePlayerSide();
        selected = null;
        targets = const [];
        _adjudicationInProgress = false;
      });
      _persistGo();
    }
    _scheduleComputerMove();
  }

  Future<void> _exportSgf() async {
    if (widget.type != GameType.go) return;
    final sgf = _persistedRecordSgf();
    try {
      final saved = await GoFileService.saveSgf(sgf);
      _notice(saved ? 'SGF 已保存或提交浏览器下载' : '已取消保存');
    } catch (e) {
      _notice('SGF 导出失败：$e');
    }
  }

  void _replaceGo(
    GameSession imported, {
    GoSgfController? record,
    String? id,
    bool computer = false,
    GoGameKind? kind,
    GoAiSettings? settings,
    Side? restoredHumanSide,
  }) {
    _computerGeneration++;
    if (_kataGo.isStarted) _kataGo.stop();
    setState(() {
      _recordKind = kind;
      _goRecord = record ?? _newRecordForSession(imported);
      if (record == null) {
        for (final move in imported.moves) {
          _goRecord.appendMove(move);
        }
        if (imported.goResignedSide != null) {
          _goRecord.appendResignation(imported.goResignedSide!);
        }
      }
      session = _goRecord.replayCurrentPath();
      _gameId = id ?? DateTime.now().microsecondsSinceEpoch.toString();
      aiSettings =
          settings ??
          GoAiSettings(
            opponentMode: computer
                ? GoOpponentMode.kataGo
                : GoOpponentMode.local,
          );
      _engineUnavailableNotified = false;
      vsComputer = computer && aiSettings.opponentMode == GoOpponentMode.kataGo;
      _panelMode = vsComputer ? _GoPanelMode.play : _GoPanelMode.choose;
      _robotPanelOpen = false;
      humanSide = restoredHumanSide ?? aiSettings.resolvePlayerSide();
      selected = null;
      targets = const [];
      computerThinking = false;
      _adjudicationInProgress = false;
    });
    _persistGo();
  }

  Future<void> _importSgf() async {
    _pauseComputer();
    try {
      final text = await pickKifuText(context);
      if (text == null || !mounted) return;
      final paths = GoSgf.variations(text);
      var selectedPath = 0;
      if (paths.length > 1) {
        final selection = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('选择复盘变化'),
            children: [
              for (var i = 0; i < paths.length; i++)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, i),
                  child: Text(paths[i].label),
                ),
            ],
          ),
        );
        if (selection == null || !mounted) return;
        selectedPath = selection;
      }
      final record = GoSgfController.fromSgf(
        text,
        variation: paths[selectedPath].choices,
      );
      _replaceGo(record.replayCurrentPath(), record: record);
      _notice(paths.length > 1 ? '已导入所选变化；导出时会保留原棋谱分支。' : 'SGF 已导入，切换为本地双人。');
    } catch (e) {
      _notice('SGF 导入失败，原棋局已保留：$e');
    } finally {
      if (mounted) {
        setState(() => _modalOpen = false);
        _scheduleComputerMove();
      }
    }
  }

  Future<void> _chooseSgfVariation() async {
    if (widget.type != GameType.go || _goRecord.current.children.isEmpty) {
      _notice('当前位置没有其他变化');
      return;
    }
    _pauseComputer();
    try {
      final selectedPath = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择后续着手'),
          children: [
            for (var i = 0; i < _goRecord.current.children.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, i),
                child: Text(_recordChildLabel(i)),
              ),
          ],
        ),
      );
      if (selectedPath != null && mounted) {
        final previous = _goRecord.current;
        if (_goRecord.navigateChild(selectedPath)) {
          try {
            setState(() {
              session = _goRecord.replayCurrentPath();
              selected = null;
              targets = const [];
            });
            await _kataGo.stop();
            await _persistGo();
          } catch (error) {
            _goRecord.navigateTo(previous);
            _notice('此变化无法重放：$error');
          }
        }
      }
    } catch (e) {
      _notice('切换变化失败：$e');
    } finally {
      if (mounted) {
        setState(() => _modalOpen = false);
        _scheduleComputerMove();
      }
    }
  }

  String _recordChildLabel(int index) {
    final node = _goRecord.current.children[index];
    if (node.resignedSide case final resigned?) {
      return '变化 ${index + 1} · ${resigned.label}认输';
    }
    final move = node.move;
    if (move == null) return '变化 ${index + 1}';
    if (move.pass) return '变化 ${index + 1} · ${move.side?.label}停一手';
    final coordinate =
        '${'ABCDEFGHJKLMNOPQRST'[move.to.col]}${session.size - move.to.row}';
    return '变化 ${index + 1} · ${move.side?.label} $coordinate';
  }

  /// Moves the record cursor to [node] and replays that path into the session.
  /// Used by the variation tree, where tapping any node jumps straight to it.
  Future<void> _navigateRecordTo(GoRecordNode node) async {
    if (widget.type != GameType.go || !_goRecord.navigateTo(node)) return;
    await _applyRecordCursor();
  }

  /// Shared tail for every record navigation: stop the engine so it cannot
  /// answer for a position the board no longer shows, replay the new cursor
  /// path, persist, then reschedule the computer move.
  Future<void> _applyRecordCursor() async {
    _computerGeneration++;
    setState(() {
      session = _goRecord.replayCurrentPath();
      selected = null;
      targets = const [];
      computerThinking = false;
      _adjudicationInProgress = false;
    });
    try {
      await _kataGo.stop();
    } catch (_) {
      // The board projection already moved to the selected record node.
    }
    await _persistGo();
    _scheduleComputerMove();
  }

  Future<void> _restoreGo() async {
    _pauseComputer();
    try {
      final text = await GoStorage.loadLast();
      final id = await GoStorage.lastId();
      final computer = await GoStorage.lastComputerMode();
      final kind = await GoStorage.lastKind();
      final restoredSettings = await GoStorage.lastAiSettings();
      final restoredHumanSide = await GoStorage.lastHumanSide();
      if (!mounted) return;
      if (text == null) {
        _notice('暂无已保存的围棋对局');
        return;
      }
      final record = GoSgfController.fromSgf(text);
      _replaceGo(
        record.replayCurrentPath(),
        record: record,
        id: id,
        computer: computer,
        kind: kind,
        settings: restoredSettings,
        restoredHumanSide: restoredHumanSide,
      );
    } catch (e) {
      _notice('恢复失败，原棋局已保留：$e');
    } finally {
      if (mounted) {
        setState(() => _modalOpen = false);
        _scheduleComputerMove();
      }
    }
  }

  Future<void> _records() async {
    _pauseComputer();
    try {
      final records = await GoStorage.records();
      if (!mounted) return;
      final text = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('本地棋谱'),
          children: records.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无棋谱'),
                  ),
                ]
              : [
                  for (var i = 0; i < records.length; i++)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, records[i]),
                      child: Text('棋谱 ${i + 1} · 点击载入'),
                    ),
                ],
        ),
      );
      if (text != null && mounted) {
        final record = GoSgfController.fromSgf(text);
        _replaceGo(record.replayCurrentPath(), record: record);
      }
    } catch (e) {
      _notice('读取棋谱失败：$e');
    } finally {
      if (mounted) {
        setState(() => _modalOpen = false);
        _scheduleComputerMove();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.type.label),
      actions: [
        IconButton(
          tooltip: '悔棋',
          onPressed: _onlineReplay || session.moves.isEmpty ? null : _undo,
          icon: const Icon(Icons.undo),
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (value) {
            if (_onlineReplay &&
                value != 'sgf' &&
                value != 'show_sgf' &&
                value != 'records') {
              return;
            }
            if (value == 'reset') _restart();
            if (value == 'records') {
              if (widget.type == GameType.go) {
                _records();
              } else {
                FeatureNotice.show(context, '对局记录');
              }
            }
            if (value == 'restore') _restoreGo();
            if (value == 'sgf') _exportSgf();
            if (value == 'import') _importSgf();
            if (value == 'variations') _chooseSgfVariation();
            if (value == 'record_tools') _chooseRecordTool();
            if (value == 'show_sgf') _showSgfText();
          },
          itemBuilder: (_) => [
            if (widget.type == GameType.go && !_onlineReplay)
              const PopupMenuItem(value: 'restore', child: Text('恢复上次对局')),
            if (widget.type == GameType.go)
              const PopupMenuItem(value: 'sgf', child: Text('导出 SGF')),
            if (widget.type == GameType.go && !_onlineReplay)
              const PopupMenuItem(value: 'import', child: Text('导入 SGF')),
            if (widget.type == GameType.go && !_onlineReplay)
              const PopupMenuItem(value: 'record_tools', child: Text('棋谱工具')),
            if (widget.type == GameType.go)
              const PopupMenuItem(
                value: 'show_sgf',
                child: Text('显示 / 复制 SGF'),
              ),
            if (widget.type == GameType.go &&
                !_onlineReplay &&
                _goRecord.current.children.isNotEmpty)
              const PopupMenuItem(value: 'variations', child: Text('切换复盘变化')),
            const PopupMenuItem(value: 'records', child: Text('对局记录')),
            if (!_onlineReplay)
              const PopupMenuItem(value: 'reset', child: Text('重新开始')),
          ],
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 760;
        final padding = wide ? 24.0 : 16.0;
        final contentWidth = math.min(
          1120.0,
          math.max(0.0, constraints.maxWidth - padding * 2),
        );
        final boardExtent = math.max(
          0.0,
          math.min(
            wide ? contentWidth - 334 : contentWidth,
            constraints.maxHeight - padding * 2,
          ),
        );
        final board = SizedBox.square(
          dimension: boardExtent,
          child: Board(
            type: widget.type,
            session: session,
            selected: selected,
            targets: targets,
            analysisHints: _analysisHints,
            analysisOwnership: _analysisOwnership,
            onCell: _onCell,
            placementMode: placementMode,
            onPreviewCell: _previewGoCell,
            onCancelPreview: _cancelGoPreview,
            annotations: widget.type == GameType.go
                ? _goRecord.current.properties
                : const {},
          ),
        );
        final side = _sidePanel(context);
        // The action bar and the record cards go under the row rather than in
        // the board's column: nesting them there would shrink the board by the
        // side panel's width, which silently moves every tap target.
        final belowBoard = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.type == GameType.go && !_onlineReplay) ...[
              _recordToolbar(context),
              if (_cardsMerged)
                _mergedCard(context)
              else ...[
                _notesCard(context),
                const SizedBox(height: 8),
                _treeCard(context),
              ],
            ] else if (_onlineReplay)
              const Text('联机对局尚未结束。此处仅供查看棋谱；请返回房间继续对局。'),
          ],
        );
        final upper = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(alignment: Alignment.topCenter, child: board),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(width: 310, child: side),
                ],
              )
            : Column(children: [board, const SizedBox(height: 16), side]);
        return SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  upper,
                  if (widget.type == GameType.go) ...[
                    const SizedBox(height: 16),
                    belowBoard,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  /// Action bar between the board and the record cards.
  ///
  /// The AI / review choice lives here rather than in the state card, so a
  /// record can switch between playing against the engine and reviewing it
  /// without reopening the new-game dialog.
  Widget _recordToolbar(BuildContext context) {
    final navEnabled = widget.type == GameType.go;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: '上一步',
              onPressed: navEnabled ? _navigateRecordPrevious : null,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: '下一步',
              onPressed: navEnabled ? _navigateRecordNext : null,
              icon: const Icon(Icons.arrow_forward),
            ),
            IconButton(
              tooltip: '上一分支点',
              onPressed: navEnabled ? _navigateRecordPreviousBranch : null,
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: '删除最后一步',
              onPressed: navEnabled && _goRecord.current.parent != null
                  ? _deleteLastNode
                  : null,
              icon: const Icon(Icons.backspace_outlined),
            ),
            // Only meaningful once the game has ended: it steps back before the
            // terminal move so the next move becomes a sibling variation.
            IconButton(
              tooltip: session.gameOver ? '续弈（在终局前接着下）' : '续弈：对局结束后可用',
              onPressed: session.gameOver ? _continueGo : null,
              icon: const Icon(Icons.play_circle_outline),
            ),
            if (!_onlineReplay)
              IconButton(
                tooltip: _robotPanelOpen ? '收起' : 'AI 与复盘',
                onPressed: () =>
                    setState(() => _robotPanelOpen = !_robotPanelOpen),
                icon: Icon(
                  _robotPanelOpen ? Icons.keyboard_arrow_up : Icons.smart_toy,
                ),
              ),
          ],
        ),
        if (_robotPanelOpen && !_onlineReplay) ...[
          const SizedBox(height: 6),
          switch (_panelMode) {
            _GoPanelMode.choose => Row(
              children: [
                Expanded(
                  child: _panelEntry(
                    icon: Icons.smart_toy_outlined,
                    label: 'AI 对弈',
                    onPressed: _startEngineGame,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _panelEntry(
                    icon: Icons.insights_outlined,
                    label: '分析',
                    onPressed: _enterReview,
                  ),
                ),
              ],
            ),
            _GoPanelMode.review => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_analysisRunning)
                  TextButton.icon(
                    onPressed: _stopAnalysis,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('停止'),
                  )
                else
                  TextButton.icon(
                    onPressed: _runAnalysis,
                    icon: const Icon(Icons.insights_outlined, size: 18),
                    label: Text(_analysis == null ? '分析' : '重新分析'),
                  ),
                // The overlays are part of the analysis, so they appear with it.
                if (_analysis != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('选点'),
                        selected: _showMoveHints,
                        onSelected: (value) =>
                            setState(() => _showMoveHints = value),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('局势'),
                        selected: _showOwnership,
                        onSelected: (value) =>
                            setState(() => _showOwnership = value),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            _GoPanelMode.play => Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _toolbarAction(
                  icon: Icons.tune,
                  label: '设置',
                  onPressed: _showGoSettings,
                ),
                _toolbarAction(
                  icon: Icons.insights_outlined,
                  label: '分析',
                  onPressed: _enterReview,
                ),
                _toolbarAction(
                  icon: Icons.pause_circle_outline,
                  label: '停一手',
                  onPressed: _canPlay ? _pass : null,
                ),
                _toolbarAction(
                  icon: Icons.undo,
                  label: '悔棋',
                  onPressed: session.moves.isEmpty ? null : _undo,
                ),
                _toolbarAction(
                  icon: Icons.flag_outlined,
                  label: '认输',
                  onPressed: session.gameOver ? null : _resign,
                ),
              ],
            ),
          },
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  /// One of the two ways into the panel, before anything has been chosen.
  Widget _panelEntry({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => FilledButton.tonalIcon(
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    label: Text(label),
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
    ),
  );

  /// One labelled action under the navigation row.
  ///
  /// The icon and its word sit together so the row reads as a menu of things the
  /// board can do, rather than requiring the icons to be memorised.
  Widget _toolbarAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool highlighted = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final colour = onPressed == null
        ? colors.onSurfaceVariant.withValues(alpha: .38)
        : highlighted
        ? colors.primary
        : colors.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: colour),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: colour)),
            ],
          ),
        ),
      ),
    );
  }

  /// Removes the last node of the current variation and steps back to it.
  ///
  /// Distinct from [_deleteCurrentNode], which acts on wherever the cursor is
  /// and asks what to do with the children. Here the node has no children by
  /// construction, so there is nothing to preserve.
  Future<void> _deleteLastNode() async {
    var node = _goRecord.current;
    while (node.children.isNotEmpty) {
      node = node.mainChild!;
    }
    if (node.parent == null) return;
    _goRecord.navigateTo(node);
    if (!_goRecord.deleteCurrent(preserveChildren: false)) return;
    await _applyRecordCursor();
    _notice('已删除最后一步');
  }

  /// Runs one bounded `kata-analyze` over the position on the board.
  ///
  /// The engine keeps the position from [_startKataGoAndReplay] onwards, so an
  /// analysis started while it is idle has to bring it up to date first.
  Future<void> _runAnalysis() async {
    if (_analysisRunning || widget.type != GameType.go || _onlineReplay) return;
    final generation = _computerGeneration;
    final node = _goRecord.current;
    setState(() {
      _analysisRunning = true;
      _analysisError = null;
    });
    try {
      if (!_androidKataGoSupported) {
        throw UnsupportedError('当前平台没有内置引擎，无法分析');
      }
      if (!_kataGo.isStarted) await _startKataGoAndReplay();
      final analysis = await _kataGo.analyze(
        boardSize: session.size,
        side: session.turn,
        budget: const Duration(seconds: 5),
      );
      if (!mounted ||
          generation != _computerGeneration ||
          !identical(node, _goRecord.current)) {
        return;
      }
      setState(() {
        _analysisResult = analysis;
        _analysisSession = session;
        _analysisDeadStones = session.deadGoStones.length;
        _analysisFocus = 0;
        _analysisRunning = false;
        // The point of analysing is to see the result, so show it.
        _showMoveHints = true;
        _noteTab = 1;
      });
    } catch (error) {
      if (!mounted || generation != _computerGeneration) return;
      setState(() {
        _analysisRunning = false;
        _analysisError = '$error';
      });
    }
  }

  Future<void> _stopAnalysis() async {
    if (!_analysisRunning) return;
    // The analysis itself reports the partial result; this only shortens it.
    await _kataGo.cancelAnalysis();
  }

  /// Candidate moves for the board badges, in rank order.
  List<Cell> get _analysisHints {
    final analysis = _analysis;
    if (analysis == null || !_showMoveHints) return const [];
    final cells = <Cell>[];
    for (final move in analysis.moves) {
      final cell = cellFromGtpVertex(move.vertex, boardSize: session.size);
      if (cell != null) cells.add(cell);
    }
    return cells;
  }

  /// Ownership wash for the board, positive being Black, or null when hidden.
  List<double>? get _analysisOwnership =>
      _showOwnership ? _analysis?.ownership : null;

  /// The candidate whose continuation the PV tab shows.
  GoAnalysisMove? get _focusedAnalysisMove {
    final analysis = _analysis;
    if (analysis == null || analysis.moves.isEmpty) return null;
    final index = _analysisFocus.clamp(0, analysis.moves.length - 1);
    return analysis.moves[index];
  }

  /// Calls the engine out: setup first, then the board actions.
  ///
  /// The two entry buttons disappear either way, which is what makes them a
  /// question rather than a mode switch.
  Future<void> _startEngineGame() async {
    setState(() => _panelMode = _GoPanelMode.play);
    // A record has nobody playing the other colour, so the question that opened
    // this dialog has already answered itself.
    await _showGoSettings(preferEngine: true);
  }

  /// Switches the panel to the engine's review of the current position.
  void _enterReview() {
    setState(() => _panelMode = _GoPanelMode.review);
    _runAnalysis();
  }

  Future<void> _navigateRecordPrevious() async {
    if (!_goRecord.navigateParent()) return;
    await _applyRecordCursor();
  }

  Future<void> _navigateRecordNext() async {
    final child = _goRecord.current.mainChild;
    if (child == null) return;
    await _navigateRecordTo(child);
  }

  /// Jumps to the nearest ancestor that has more than one continuation.
  Future<void> _navigateRecordPreviousBranch() async {
    var parent = _goRecord.current.parent;
    while (parent != null && !parent.isVariationPoint) {
      parent = parent.parent;
    }
    if (parent == null) return;
    await _navigateRecordTo(parent);
  }

  /// Collapsible bottom card with two tabs, as in the reference layout.
  /// Extracted as its own widget so the panel chrome stays out of the already
  /// long side panel.
  Widget _panelCard({
    required List<String> tabs,
    required int selected,
    required ValueChanged<int> onSelect,
    required bool collapsed,
    required VoidCallback onToggleCollapse,
    required Widget child,
  }) => Card(
    elevation: 0,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                _panelTab(
                  context,
                  tabs[i],
                  selected: i == selected,
                  onTap: collapsed
                      ? () {
                          onToggleCollapse();
                          onSelect(i);
                        }
                      : () => onSelect(i),
                ),
              const Spacer(),
              IconButton(
                tooltip: collapsed ? '展开面板' : '收起面板',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleCollapse,
                icon: Icon(
                  collapsed
                      ? Icons.crop_square_outlined
                      : Icons.crop_16_9_outlined,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        if (!collapsed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: child,
          ),
      ],
    ),
  );

  Widget _panelTab(
    BuildContext context,
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Container(
        padding: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );

  /// Tabs: notes / AI summary.
  Widget _notesCard(BuildContext context) => _panelCard(
    tabs: const ['注释', 'AI 摘要'],
    selected: _noteTab,
    onSelect: (value) => setState(() => _noteTab = value),
    collapsed: _noteCollapsed,
    onToggleCollapse: () => setState(() {
      _cardsMerged = true;
      _mergedTab = _noteTab;
    }),
    child: _noteTab == 0 ? _commentBody(context) : _analysisBody(context),
  );

  /// Tabs: variation tree / principal variation.
  Widget _treeCard(BuildContext context) => _panelCard(
    tabs: const ['变化树', 'PV'],
    selected: _treeTab,
    onSelect: (value) => setState(() => _treeTab = value),
    collapsed: _treeCollapsed,
    onToggleCollapse: () => setState(() {
      _cardsMerged = true;
      _mergedTab = _treeTab + 2;
    }),
    child: _treeTab == 0 ? _treeBody(context) : _pvBody(context),
  );

  /// Four tabs in one card. Either card's collapse button merges them, and the
  /// tab the user was on is kept, which is why the selected index is shared.
  Widget _mergedCard(BuildContext context) => _panelCard(
    tabs: const ['注释', 'AI 摘要', '变化树', 'PV'],
    selected: _mergedTab,
    onSelect: (value) => setState(() => _mergedTab = value),
    collapsed: false,
    onToggleCollapse: () => setState(() {
      _cardsMerged = false;
      // Keep whatever tab was showing in the card it belongs to.
      if (_mergedTab <= 1) {
        _noteTab = _mergedTab;
      } else {
        _treeTab = _mergedTab - 2;
      }
    }),
    child: switch (_mergedTab) {
      0 => _commentBody(context),
      1 => _analysisBody(context),
      2 => _treeBody(context),
      _ => _pvBody(context),
    },
  );

  Widget _commentBody(BuildContext context) {
    final comment = _goRecord.current.properties['C']?.firstOrNull;
    return InkWell(
      onTap: _editComment,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          comment == null || comment.isEmpty ? '暂无注释，点击编辑。' : comment,
          style: TextStyle(
            fontStyle: comment == null || comment.isEmpty
                ? FontStyle.italic
                : FontStyle.normal,
            color: comment == null || comment.isEmpty
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : null,
          ),
        ),
      ),
    );
  }

  /// Engine review of the current position: a one-line verdict plus the ranked
  /// candidate moves the board badges refer to by number.
  Widget _analysisBody(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final analysis = _analysis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _analysisRunning
                    ? '正在分析…'
                    : analysis == null
                    ? '暂无分析'
                    : _analysisVerdict(analysis),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (_analysisRunning)
              TextButton.icon(
                onPressed: _stopAnalysis,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('停止'),
              )
            else
              FilledButton.tonalIcon(
                onPressed: _runAnalysis,
                icon: const Icon(Icons.insights_outlined, size: 18),
                label: Text(analysis == null ? '分析' : '重新分析'),
              ),
          ],
        ),
        if (_analysisError != null) ...[
          const SizedBox(height: 4),
          Text('分析失败：$_analysisError', style: muted),
        ],
        if (analysis != null && analysis.moves.isNotEmpty) ...[
          const SizedBox(height: 8),
          _analysisTable(context, analysis),
        ] else if (!_analysisRunning && _analysisError == null) ...[
          const SizedBox(height: 8),
          Text('点击「分析」让引擎评估当前局面。', style: muted),
        ],
      ],
    );
  }

  /// One-line summary of the position, always read from Black's side.
  String _analysisVerdict(GoAnalysis analysis) {
    final winRate = (analysis.rootWinRate * 100).toStringAsFixed(1);
    final lead = analysis.rootScoreLead;
    final leader = lead >= 0 ? '黑' : '白';
    return '黑棋胜率 $winRate%   $leader棋领先 ${lead.abs().toStringAsFixed(1)} 目'
        '   搜索 ${analysis.rootVisits}';
  }

  Widget _analysisTable(BuildContext context, GoAnalysis analysis) {
    final theme = Theme.of(context);
    final header = TextStyle(
      fontSize: 11,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(width: 28, child: Text('序号', style: header)),
              SizedBox(width: 48, child: Text('着点', style: header)),
              Expanded(child: Text('胜率', style: header)),
              Expanded(child: Text('目差', style: header)),
              Expanded(child: Text('搜索量', style: header)),
              Expanded(child: Text('占比', style: header)),
            ],
          ),
        ),
        const Divider(height: 8),
        for (var i = 0; i < analysis.moves.length; i++)
          _analysisRow(context, analysis, i),
      ],
    );
  }

  Widget _analysisRow(BuildContext context, GoAnalysis analysis, int index) {
    final theme = Theme.of(context);
    final move = analysis.moves[index];
    final focused = index == _analysisFocus.clamp(0, analysis.moves.length - 1);
    final label = TextStyle(
      fontSize: 12,
      fontWeight: focused ? FontWeight.bold : FontWeight.normal,
      color: focused ? theme.colorScheme.primary : null,
    );
    return InkWell(
      // Selecting a row retargets the PV tab rather than playing the move: the
      // board must keep showing the position the numbers were computed for.
      onTap: () => setState(() => _analysisFocus = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 28, child: Text('${index + 1}', style: label)),
            SizedBox(width: 48, child: Text(move.vertex, style: label)),
            Expanded(
              child: Text(
                '${(move.winRate * 100).toStringAsFixed(1)}%',
                style: label,
              ),
            ),
            Expanded(
              child: Text(
                '${move.scoreLead >= 0 ? '+' : '-'}'
                '${move.scoreLead.abs().toStringAsFixed(1)}',
                style: label,
              ),
            ),
            Expanded(child: Text('${move.visits}', style: label)),
            Expanded(
              child: Text(
                '${(move.shareOf(analysis.rootVisits) * 100).toStringAsFixed(0)}%',
                style: label,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _treeBody(BuildContext context) {
    if (widget.type != GameType.go) {
      return Text(
        '仅围棋支持变化树。',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              _goRecord.current.isRoot
                  ? '棋谱起点'
                  : '第 ${GoVariationLayout.moveNumber(_goRecord.current)} 手',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (_goRecord.current.children.isNotEmpty)
              TextButton.icon(
                onPressed: _chooseSgfVariation,
                icon: const Icon(Icons.fork_right, size: 18),
                label: const Text('选择后续变化'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GoVariationTree(
          root: _goRecord.root,
          current: _goRecord.current,
          onSelect: _navigateRecordTo,
        ),
      ],
    );
  }

  Widget _pvBody(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(
      fontSize: 13,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final move = _focusedAnalysisMove;
    if (move == null) {
      return Text('暂无 PV。先在上方「AI 摘要」里分析当前局面。', style: muted);
    }
    final analysis = _analysis!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '第 ${_analysisFocus.clamp(0, analysis.moves.length - 1) + 1} 选点',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(width: 8),
            Text(
              '${(move.winRate * 100).toStringAsFixed(1)}%  '
              '${move.scoreLead >= 0 ? '+' : '-'}'
              '${move.scoreLead.abs().toStringAsFixed(1)} 目',
              style: muted,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (move.pv.isEmpty)
          Text('引擎还没有给出后续变化。', style: muted)
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < move.pv.length; i++)
                Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  // Blue for Black's moves and the default surface for White
                  // mirrors the stones, so the colour of a move is obvious.
                  backgroundColor: i.isEven
                      ? theme.colorScheme.primaryContainer
                      : null,
                  label: Text(
                    '${_analysisMoveNumber(analysis, i)} ${move.pv[i]}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// Move number of the [index]-th PV entry, continuing from the analysis.
  int _analysisMoveNumber(GoAnalysis analysis, int index) =>
      session.moves.length + index + 1;

  Widget _sidePanel(BuildContext context) {
    if (_onlineReplay) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('联机对局进行中 · ${session.moves.length} 手\n棋谱只读，终局后可使用分析。'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.turnLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (computerThinking)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '电脑思考中…',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  widget.type == GameType.go
                      ? '提子：黑 ${session.blackCaptures} · 白 ${session.whiteCaptures}'
                      : '吃子：黑 ${session.blackCaptures} · 白 ${session.whiteCaptures}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (widget.type == GameType.go && session.gameOver) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${session.goScoreConfirmed ? '结果' : '估算'}：${session.calculateGoScore().result}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    session.goScoreConfirmed
                        ? (session.goResignedSide != null
                              ? 'KataGo 已认输'
                              : '计分已确认')
                        : _adjudicationInProgress
                        ? 'KataGo 正在裁定死活与终局结果…'
                        : '点击整块棋标记死子（红叉）；确认后结束计分。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  if (!session.goScoreConfirmed)
                    TextButton(
                      onPressed: _adjudicationInProgress
                          ? null
                          : () {
                              setState(() => session.confirmGoScore());
                              _persistGo();
                            },
                      child: const Text('确认计分'),
                    ),
                  TextButton(
                    onPressed: _adjudicationInProgress ? null : _continueGo,
                    child: const Text('继续对局'),
                  ),
                ],
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.type == GameType.go
                            ? '围棋 ${session.size} × ${session.size}'
                            : '棋盘 8 × 8',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '${session.moves.length} 手',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '招法',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 108,
                  child: session.moves.isEmpty
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            '选择一个空位或棋子开始。',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: session.moves.length,
                          itemBuilder: (context, index) {
                            final move = session.moves[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '${index + 1}. ${_moveText(move)}${move.captured ? '  吃子' : ''}${move.pass ? '（停一手）' : ''}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        if (widget.type == GameType.go)
          OutlinedButton.icon(
            onPressed: _canPlay ? _pass : null,
            icon: const Icon(Icons.skip_next),
            label: const Text('停一手'),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _restart,
          icon: const Icon(Icons.restart_alt),
          label: const Text('重新开始'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: session.moves.isEmpty ? null : _undo,
          icon: const Icon(Icons.undo),
          label: const Text('悔棋'),
        ),
      ],
    );
  }

  String _moveText(GameMove move) {
    if (move.pass) return '';
    final to = move.to;
    if (widget.type == GameType.go) {
      return '${'ABCDEFGHJKLMNOPQRST'[to.col]}${session.size - to.row}';
    }
    final dest = '${String.fromCharCode(65 + to.col)}${8 - to.row}';
    if (move.from == null) return dest;
    final from =
        '${String.fromCharCode(65 + move.from!.col)}${8 - move.from!.row}';
    return '$from → $dest';
  }
}

class FeatureNotice {
  static Future<void> show(BuildContext context, String feature) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(feature),
          content: const Text('这个功能还在开发中，目前可以开始本地对局。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
}
