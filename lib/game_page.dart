import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'game_session.dart';
import 'go_file_service.dart';
import 'go_sgf.dart';
import 'go_storage.dart';
import 'go_ai_settings.dart';
import 'go_models.dart';
import 'go_model_manager.dart';
import 'go_engine_profiles.dart';
import 'go_engine_manager.dart';
import 'go_engine_runtime.dart';
import 'katago.dart';
import 'board.dart';
import 'go_placement.dart';

extension GameTypeX on GameType {
  String get label => switch (this) {
    GameType.go => '围棋',
    GameType.chess => '国际象棋',
    GameType.checkers => '跳棋',
  };
  String get english => switch (this) {
    GameType.go => 'GO',
    GameType.chess => 'CHESS',
    GameType.checkers => 'CHECKERS',
  };
  String get description => switch (this) {
    GameType.go => '在方寸之间，寻找全局的平衡',
    GameType.chess => '经典战略，驾驭每一步',
    GameType.checkers => '轻快对弈，跳出你的节奏',
  };
  IconData get icon => switch (this) {
    GameType.go => Icons.blur_on,
    GameType.chess => Icons.castle,
    GameType.checkers => Icons.grid_4x4,
  };
}

class _GoGameSetup {
  final GoConfig goConfig;
  final GoAiSettings aiSettings;
  const _GoGameSetup(this.goConfig, this.aiSettings);
}

class GamePage extends StatefulWidget {
  final GameType type;
  final GoConfig? goConfig;
  final GoAiSettings? aiSettings;
  final bool? useAndroidKataGo;
  const GamePage({
    super.key,
    required this.type,
    this.goConfig,
    this.aiSettings,
    this.useAndroidKataGo,
  });
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late GameSession session;
  late GoAiSettings aiSettings;
  bool vsComputer = true;
  Side humanSide = Side.black;
  bool computerThinking = false;
  int _computerGeneration = 0;
  bool _modalOpen = false;
  bool _adjudicationInProgress = false;
  String _gameId = DateTime.now().microsecondsSinceEpoch.toString();
  String? _sgfSource;
  final KataGoAndroidRuntime _kataGo = KataGoAndroidRuntime();
  final KataGoWebRuntime _webKataGo = KataGoWebRuntime();
  bool _engineUnavailableNotified = false;
  GoPlacementMode placementMode = GoPlacementMode.automatic;

  bool get _canPlay =>
      !_modalOpen &&
      !session.gameOver &&
      !computerThinking &&
      (!vsComputer || session.turn == humanSide);

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
    _notice('KataGo 不可用，已切换为本地双人模式：$reason');
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
    aiSettings = widget.aiSettings ?? const GoAiSettings();
    vsComputer = aiSettings.opponentMode != GoOpponentMode.local;
    humanSide = aiSettings.resolvePlayerSide();
    GoPlacementPreferences.load().then((value) {
      if (mounted) setState(() => placementMode = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.type == GameType.go) {
        _showGoSettings(requiredAtStart: true);
      }
    });
  }

  void _previewGoCell(Cell cell) {
    if (widget.type != GameType.go || !_canPlay) return;
    if (!session.isLegalGoMove(cell)) return;
    setState(() => selected = cell);
  }

  void _cancelGoPreview() {
    if (widget.type != GameType.go) return;
    if (selected != null) setState(() => selected = null);
  }

  void _onCell(Cell cell) {
    if (_modalOpen || _adjudicationInProgress) return;
    if (session.gameOver && widget.type == GameType.go) {
      setState(() => session.toggleDeadGoStone(cell));
      _persistGo();
      return;
    }
    if (!_canPlay) return;
    final before = session.moves.length;
    setState(() {
      if (widget.type == GameType.go) {
        session.placeGo(cell);
        selected = null;
        targets = const [];
      } else if (selected == null) {
        if (session.pieceAt(cell)?.side == session.turn) {
          selected = cell;
          targets = session.legalMovesFrom(cell);
        }
      } else if (targets.contains(cell)) {
        session.movePiece(selected!, cell);
        selected = null;
        targets = const [];
      } else if (session.pieceAt(cell)?.side == session.turn) {
        selected = cell;
        targets = session.legalMovesFrom(cell);
      } else {
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

  Future<void> _undoKataGo(int count) async {
    if (!_kataGo.isStarted) return;
    for (var i = 0; i < count; i++) {
      await _kataGo.send('undo');
    }
  }

  Future<void> _persistGo() async {
    if (widget.type != GameType.go) return;
    try {
      await GoStorage.saveLast(
        GoSgf.exportGame(session),
        gameId: _gameId,
        vsComputer: vsComputer,
        aiSettings: aiSettings,
        humanSide: humanSide,
      );
    } catch (e) {
      _notice('棋局未保存，请导出 SGF 备份：$e');
    }
  }

  void _scheduleComputerMove() {
    if (!mounted ||
        _modalOpen ||
        !vsComputer ||
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
      if (widget.type == GameType.go &&
          _usesKataGo &&
          _androidKataGoSupported) {
        try {
          if (!_kataGo.isStarted) await _startKataGoAndReplay();
          if (!mounted || generation != _computerGeneration) return;
          final vertex = (await _kataGo.send(
            'genmove ${session.turn == Side.black ? 'B' : 'W'}',
          )).trim();
          if (!mounted || generation != _computerGeneration) return;
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
          if (!mounted || generation != _computerGeneration) return;
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
    if (vertex.toLowerCase() == 'pass') return session.passGo();
    if (vertex.toLowerCase() == 'resign') return session.resignGo();
    return session.placeGo(_cellFromGtp(vertex));
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
      if (undoCount == 2) {
        session.undo();
        session.undo();
      } else {
        session.undo();
      }
    });
    try {
      await _undoKataGo(undoCount);
    } catch (_) {
      await _kataGo.stop();
    }
    _persistGo();
    _scheduleComputerMove();
  }

  Future<void> _restart() async {
    final generation = ++_computerGeneration;
    setState(() {
      _gameId = DateTime.now().microsecondsSinceEpoch.toString();
      session.reset();
      _sgfSource = null;
      selected = null;
      targets = const [];
      computerThinking = false;
      _adjudicationInProgress = false;
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
    setState(() => session.passGo());
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

  Future<void> _autoAdjudicate(int generation) async {
    if (_adjudicationInProgress || !session.gameOver || !mounted) return;
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
      if (!mounted || generation != _computerGeneration) return;
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
      if (!mounted || generation != _computerGeneration) return;
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

  Future<void> _showGoSettings({bool requiredAtStart = false}) async {
    if (widget.type != GameType.go) return;
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
    var mode = aiSettings.opponentMode;
    var playerColor = aiSettings.playerColor;
    var rank = aiSettings.rank;
    var style = aiSettings.style;
    var humanModelId = aiSettings.humanModelId;
    var humanRank = aiSettings.resolvedHumanStyleRank;
    final humanProfile = TextEditingController(
      text: aiSettings.humanSLProfile ?? '',
    );
    var useBuiltinHumanStyle = aiSettings.useBuiltinHumanStyle;
    var availableModels = <GoModelInfo>[GoModelLibrary.bundledModel];
    var activeModel = GoModelLibrary.bundledId;
    var engines = <GoEngineProfile>[GoEngineProfile.builtIn];
    var activeEngine = GoEngineProfile.builtIn.id;
    try {
      availableModels = await GoModelLibrary.available();
      activeModel = await GoModelLibrary.activeId();
      engines = await GoEngineLibrary.available();
      activeEngine = await GoEngineLibrary.activeId();
    } catch (error) {
      _notice('读取 KataGo 模型列表失败，暂用内置 b6 模型：$error');
    }
    var modelId = kIsWeb
        ? GoModelLibrary.bundledId
        : requiredAtStart && widget.aiSettings == null
        ? activeModel
        : availableModels.any((model) => model.id == aiSettings.modelId)
        ? aiSettings.modelId
        : activeModel;
    var engineProfileId = requiredAtStart && widget.aiSettings == null
        ? activeEngine
        : engines.any((engine) => engine.id == aiSettings.engineProfileId)
        ? aiSettings.engineProfileId
        : activeEngine;
    void applyModelSelection() {
      useBuiltinHumanStyle = availableModels
          .firstWhere((m) => m.id == modelId)
          .isHumanModel;
      if (useBuiltinHumanStyle) {
        humanModelId = null;
        style = GoAiStyle.human;
      }
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
      applyModelSelection();
      if (humanModelId != null) {
        style = GoAiStyle.human;
      } else if (!useBuiltinHumanStyle && style == GoAiStyle.human) {
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
            title: Text(requiredAtStart ? '新建 AI 对局' : '对局设置'),
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
                    Text(
                      'AI 设置',
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    _setupField(
                      '对局模式',
                      DropdownButtonFormField<GoOpponentMode>(
                        initialValue: mode,
                        decoration: const InputDecoration(),
                        items: const [
                          DropdownMenuItem(
                            value: GoOpponentMode.kataGo,
                            child: Text('人机 · KataGo'),
                          ),
                          DropdownMenuItem(
                            value: GoOpponentMode.local,
                            child: Text('本地双人'),
                          ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => mode = value ?? mode),
                      ),
                    ),
                    if (mode != GoOpponentMode.local) ...[
                      const SizedBox(height: 8),
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
                    ],
                    if (mode == GoOpponentMode.kataGo) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _setupField(
                            'AI 引擎',
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              key: ValueKey(engineProfileId),
                              initialValue: engineProfileId,
                              decoration: const InputDecoration(),
                              items: engines
                                  .map(
                                    (engine) => DropdownMenuItem(
                                      value: engine.id,
                                      child: Text(engine.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setDialogState(() {
                                engineProfileId = value ?? engineProfileId;
                                applyEngineSelection();
                              }),
                            ),
                          ),
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
                            items: GoAiRank.values
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
                      _setupField(
                        '风格',
                        DropdownButtonFormField<GoAiStyle>(
                          key: ValueKey(style),
                          initialValue: style,
                          decoration: const InputDecoration(),
                          items: GoAiStyle.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                              )
                              .toList(),
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
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('使用主模型内置人类棋风'),
                          subtitle: const Text('启用后不再加载独立 human model'),
                          value: useBuiltinHumanStyle,
                          onChanged: (value) => setDialogState(() {
                            useBuiltinHumanStyle = value;
                            if (value) humanModelId = null;
                          }),
                        ),
                        if (!useBuiltinHumanStyle)
                          _setupField(
                            '人类棋风模型',
                            DropdownButtonFormField<String?>(
                              isExpanded: true,
                              key: ValueKey(humanModelId),
                              initialValue: humanModelId,
                              decoration: const InputDecoration(
                                hintText: '请选择已导入的人类棋风模型',
                              ),
                              items: availableModels
                                  .where(
                                    (model) => model.kind == GoModelKind.human,
                                  )
                                  .map(
                                    (model) => DropdownMenuItem<String?>(
                                      value: model.id,
                                      child: Text(model.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setDialogState(() => humanModelId = value),
                            ),
                          ),
                      ],
                      _setupField(
                        '模型',
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                key: ValueKey(modelId),
                                initialValue: modelId,
                                decoration: const InputDecoration(),
                                items: availableModels
                                    .map(
                                      (model) => DropdownMenuItem(
                                        value: model.id,
                                        child: Text(
                                          model.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setDialogState(() {
                                  modelId = value ?? modelId;
                                  applyModelSelection();
                                }),
                              ),
                            ),
                            IconButton(
                              tooltip: '管理模型',
                              onPressed: () async {
                                try {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const GoModelManagerPage(),
                                    ),
                                  );
                                  final models =
                                      await GoModelLibrary.available();
                                  final active =
                                      await GoModelLibrary.activeId();
                                  final profiles =
                                      await GoEngineLibrary.available();
                                  final activeProfile =
                                      await GoEngineLibrary.activeId();
                                  if (!context.mounted) return;
                                  setDialogState(() {
                                    availableModels = models;
                                    modelId = active;
                                    if (humanModelId != null &&
                                        !models.any(
                                          (m) => m.id == humanModelId,
                                        )) {
                                      humanModelId = null;
                                    }
                                    engines = profiles;
                                    engineProfileId = activeProfile;
                                    applyModelSelection();
                                  });
                                } catch (error) {
                                  if (context.mounted) {
                                    setDialogState(
                                      () => setupError = '读取模型列表失败：$error',
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.settings_outlined),
                            ),
                          ],
                        ),
                      ),
                      if (engines
                              .firstWhere((e) => e.id == engineProfileId)
                              .backend ==
                          GoEngineBackend.opencl)
                        TextButton.icon(
                          icon: const Icon(Icons.speed),
                          label: const Text('检测 GPU / 调优当前配置'),
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GoEngineRuntimePage(
                                  profile: engines.firstWhere(
                                    (e) => e.id == engineProfileId,
                                  ),
                                  config: GoConfig(
                                    boardSize: size,
                                    rules: rules,
                                    komi: double.parse(komiController.text),
                                    handicap: handicap,
                                  ),
                                  settings: GoAiSettings(
                                    modelId: modelId,
                                    engineProfileId: engineProfileId,
                                    rank: rank,
                                    style: style,
                                    humanStyleRank: humanRank,
                                    humanSLProfile:
                                        humanProfile.text.trim().isEmpty
                                        ? null
                                        : humanProfile.text.trim(),
                                    humanModelId:
                                        style == GoAiStyle.human &&
                                            !useBuiltinHumanStyle
                                        ? humanModelId
                                        : null,
                                    useBuiltinHumanStyle:
                                        style == GoAiStyle.human &&
                                        useBuiltinHumanStyle,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
                            await GoModelLibrary.load(modelId);
                            final selectedModel = await GoModelLibrary.byId(
                              modelId,
                            );
                            final selectedEngine = await GoEngineLibrary.byId(
                              engineProfileId,
                            );
                            final human =
                                style != GoAiStyle.human ||
                                    useBuiltinHumanStyle ||
                                    humanModelId == null
                                ? null
                                : await GoModelLibrary.byId(humanModelId!);
                            final checkedSettings = GoAiSettings(
                              style: style,
                              humanModelId: human?.id,
                              humanStyleRank: humanRank,
                              humanSLProfile: humanProfile.text.trim().isEmpty
                                  ? null
                                  : humanProfile.text.trim(),
                              useBuiltinHumanStyle:
                                  style == GoAiStyle.human &&
                                  useBuiltinHumanStyle,
                            );
                            checkedSettings.validateHumanStyle();
                            if (human != null) {
                              await GoModelLibrary.load(human.id);
                            }
                            GoModelCompatibility.validate(
                              model: selectedModel,
                              engine: selectedEngine,
                              humanModel: human,
                              useBuiltinHumanStyle:
                                  style == GoAiStyle.human &&
                                  useBuiltinHumanStyle,
                            );
                            if (selectedModel.isHumanModel &&
                                style != GoAiStyle.human) {
                              throw StateError('人类棋风主模型需要选择人类棋风和有效段位');
                            }
                            if (style == GoAiStyle.human &&
                                !useBuiltinHumanStyle &&
                                human == null) {
                              throw StateError('人类棋风模式需要选择 human model');
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
                              humanModelId:
                                  style == GoAiStyle.human &&
                                      !useBuiltinHumanStyle
                                  ? humanModelId
                                  : null,
                              humanStyleRank: humanRank,
                              humanSLProfile: humanProfile.text.trim().isEmpty
                                  ? null
                                  : humanProfile.text.trim(),
                              useBuiltinHumanStyle:
                                  style == GoAiStyle.human &&
                                  useBuiltinHumanStyle,
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
                    : Text(requiredAtStart ? '开始对局' : '应用并重开'),
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
      setState(() {
        _gameId = DateTime.now().microsecondsSinceEpoch.toString();
        session.setGoConfig(result.goConfig);
        aiSettings = result.aiSettings;
        vsComputer = aiSettings.opponentMode != GoOpponentMode.local;
        _engineUnavailableNotified = false;
        humanSide = aiSettings.resolvePlayerSide();
        _sgfSource = null;
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
    final sgf = GoSgf.exportGame(session);
    try {
      final saved = await GoFileService.saveSgf(sgf);
      _notice(saved ? 'SGF 已保存或提交浏览器下载' : '已取消保存');
    } catch (e) {
      _notice('SGF 导出失败：$e');
    }
  }

  void _replaceGo(
    GameSession imported, {
    String? id,
    bool computer = false,
    GoAiSettings? settings,
    Side? restoredHumanSide,
    String? source,
  }) {
    _computerGeneration++;
    _kataGo.stop();
    setState(() {
      session = imported;
      _sgfSource = source;
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
      final text = await GoFileService.pickSgf();
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
      _replaceGo(
        GoSgf.importGame(text, variation: paths[selectedPath].choices),
        source: text,
      );
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
    final source = _sgfSource;
    if (source == null || widget.type != GameType.go) return;
    final paths = GoSgf.variations(source);
    if (paths.length < 2) {
      _notice('当前棋谱没有其他变化');
      return;
    }
    _pauseComputer();
    try {
      if (!mounted) return;
      final selectedPath = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('切换复盘变化'),
          children: [
            for (var i = 0; i < paths.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, i),
                child: Text(paths[i].label),
              ),
          ],
        ),
      );
      if (selectedPath != null && mounted) {
        _replaceGo(
          GoSgf.importGame(source, variation: paths[selectedPath].choices),
          source: source,
        );
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

  Future<void> _restoreGo() async {
    _pauseComputer();
    try {
      final text = await GoStorage.loadLast();
      final id = await GoStorage.lastId();
      final computer = await GoStorage.lastComputerMode();
      final restoredSettings = await GoStorage.lastAiSettings();
      final restoredHumanSide = await GoStorage.lastHumanSide();
      if (!mounted) return;
      if (text == null) {
        _notice('暂无已保存的围棋对局');
        return;
      }
      _replaceGo(
        GoSgf.importGame(text),
        id: id,
        computer: computer,
        settings: restoredSettings,
        restoredHumanSide: restoredHumanSide,
        source: text,
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
          title: const Text('本地棋谱（最近20盘）'),
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
      if (text != null && mounted) _replaceGo(GoSgf.importGame(text));
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
          onPressed: session.moves.isEmpty ? null : _undo,
          icon: const Icon(Icons.undo),
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (value) {
            if (value == 'pass' && widget.type == GameType.go) _pass();
            if (value == 'reset') _restart();
            if (value == 'records') {
              if (widget.type == GameType.go) {
                _records();
              } else {
                FeatureNotice.show(context, '对局记录');
              }
            }
            if (value == 'restore') _restoreGo();
            if (value == 'settings') _showGoSettings();
            if (value == 'sgf') _exportSgf();
            if (value == 'import') _importSgf();
            if (value == 'variations') _chooseSgfVariation();
          },
          itemBuilder: (_) => [
            if (widget.type == GameType.go)
              PopupMenuItem(
                value: 'pass',
                enabled: _canPlay,
                child: const Text('停一手'),
              ),
            if (widget.type == GameType.go)
              const PopupMenuItem(value: 'restore', child: Text('恢复上次对局')),
            if (widget.type == GameType.go)
              const PopupMenuItem(value: 'settings', child: Text('棋盘与规则设置')),
            if (widget.type == GameType.go)
              const PopupMenuItem(value: 'sgf', child: Text('导出 SGF')),
            if (widget.type == GameType.go)
              const PopupMenuItem(value: 'import', child: Text('导入 SGF')),
            if (widget.type == GameType.go && _sgfSource != null)
              const PopupMenuItem(value: 'variations', child: Text('切换复盘变化')),
            const PopupMenuItem(value: 'records', child: Text('对局记录')),
            const PopupMenuItem(value: 'reset', child: Text('重新开始')),
          ],
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 760;
        final board = Board(
          type: widget.type,
          session: session,
          selected: selected,
          targets: targets,
          onCell: _onCell,
          placementMode: placementMode,
          onPreviewCell: _previewGoCell,
          onCancelPreview: _cancelGoPreview,
        );
        final side = _sidePanel(context);
        return SingleChildScrollView(
          padding: EdgeInsets.all(wide ? 24 : 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: board),
                        const SizedBox(width: 24),
                        SizedBox(width: 310, child: side),
                      ],
                    )
                  : Column(children: [board, const SizedBox(height: 16), side]),
            ),
          ),
        );
      },
    ),
  );

  Widget _sidePanel(BuildContext context) => Column(
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
              if (session.isInCheckTurn && !session.gameOver)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '将军',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(
                      KataGoAndroidRuntime.isSupported ||
                              KataGoWebRuntime.isSupported
                          ? '电脑（KataGo ${aiSettings.rank.label}）'
                          : '电脑（KataGo）',
                    ),
                    icon: Icon(Icons.smart_toy_outlined),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('本地双人'),
                    icon: Icon(Icons.people_outline),
                  ),
                ],
                selected: {vsComputer},
                onSelectionChanged: (value) {
                  _computerGeneration++;
                  setState(() {
                    vsComputer = value.first;
                    aiSettings = aiSettings.copyWith(
                      opponentMode: value.first
                          ? GoOpponentMode.kataGo
                          : GoOpponentMode.local,
                    );
                    if (value.first) _engineUnavailableNotified = false;
                    computerThinking = false;
                    _adjudicationInProgress = false;
                    selected = null;
                    targets = const [];
                  });
                  _persistGo();
                  _scheduleComputerMove();
                },
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
                  onPressed: _adjudicationInProgress
                      ? null
                      : () {
                          setState(() => session.resumeGo());
                          _persistGo();
                          _scheduleComputerMove();
                        },
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
