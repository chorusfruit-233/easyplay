import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../board.dart';
import '../../draughts/draughts_session.dart';
import '../../draughts/widgets/draughts_board.dart';
import '../../game_session.dart';
import '../../gomoku/gomoku_session.dart';
import '../../gomoku/widgets/gomoku_board.dart';
import '../record_playback_controller.dart';
import '../record_replay.dart';

class RecordPlaybackPage extends StatefulWidget {
  const RecordPlaybackPage({super.key, required this.record});

  final RecordReplay record;

  @override
  State<RecordPlaybackPage> createState() => _RecordPlaybackPageState();
}

class _RecordPlaybackPageState extends State<RecordPlaybackPage>
    with WidgetsBindingObserver {
  late final RecordPlaybackController _player;

  @override
  void initState() {
    super.initState();
    _player = RecordPlaybackController(
      widget.record,
      canAdvance: () => ModalRoute.of(context)?.isCurrent ?? false,
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Widget _board() => IgnorePointer(
    child: switch (_player.frame.session) {
      final GameSession session => Board(
        type: GameType.go,
        session: session,
        selected: null,
        targets: const [],
        onCell: (_) {},
        annotations: _player.frame.annotations,
      ),
      final GomokuSession session => GomokuBoard(
        session: session,
        enabled: false,
        onCell: (_) {},
      ),
      final DraughtsSession session => DraughtsBoard(
        session: session,
        onCell: (_) {},
      ),
      _ => const SizedBox.shrink(),
    },
  );

  Widget _controls() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      Text(
        _player.frame.description,
        key: const ValueKey('record-playback-description'),
        style: Theme.of(context).textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        '${_player.position} / ${_player.length} 步${_player.position == _player.length && _player.length > 0 ? ' · 播放完毕' : ''}',
        key: const ValueKey('record-playback-progress'),
        textAlign: TextAlign.center,
      ),
      Slider(
        key: const ValueKey('record-playback-slider'),
        value: _player.position.toDouble(),
        max: math.max(1, _player.length).toDouble(),
        divisions: _player.length > 0 ? _player.length : null,
        label: '${_player.position} / ${_player.length}',
        semanticFormatterCallback: (value) =>
            '第 ${value.round()} 步，共 ${_player.length} 步',
        onChangeStart: (_) => _player.pause(),
        onChanged: _player.length == 0
            ? null
            : (value) => _player.seek(value.round()),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        children: [
          IconButton(
            key: const ValueKey('record-playback-first'),
            tooltip: '回到开局',
            onPressed: _player.position == 0 ? null : () => _player.seek(0),
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            key: const ValueKey('record-playback-previous'),
            tooltip: '上一步',
            onPressed: _player.position == 0
                ? null
                : () => _player.seek(_player.position - 1),
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton.filled(
            key: const ValueKey('record-playback-toggle'),
            tooltip: _player.playing
                ? '暂停播放'
                : _player.position == _player.length && _player.length > 0
                ? '重新播放'
                : '播放棋谱',
            onPressed: _player.length == 0
                ? null
                : _player.playing
                ? _player.pause
                : _player.play,
            icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(
            key: const ValueKey('record-playback-next'),
            tooltip: '下一步',
            onPressed: _player.position == _player.length
                ? null
                : () => _player.seek(_player.position + 1),
            icon: const Icon(Icons.skip_next),
          ),
          IconButton(
            key: const ValueKey('record-playback-last'),
            tooltip: '跳到末尾',
            onPressed: _player.position == _player.length
                ? null
                : () => _player.seek(_player.length),
            icon: const Icon(Icons.last_page),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('播放速度'),
          DropdownButton<double>(
            key: const ValueKey('record-playback-speed'),
            value: _player.speed,
            items: const [
              DropdownMenuItem(value: .5, child: Text('0.5×')),
              DropdownMenuItem(value: 1, child: Text('1×')),
              DropdownMenuItem(value: 2, child: Text('2×')),
            ],
            onChanged: (speed) {
              if (speed != null) _player.setSpeed(speed);
            },
          ),
          if (_player.record case final GoRecordReplay go)
            if (go.variations.length > 1)
              DropdownButton<int>(
                key: const ValueKey('record-playback-variation'),
                value: go.variation,
                items: [
                  for (var i = 0; i < go.variations.length; i++)
                    DropdownMenuItem(value: i, child: Text(go.variations[i])),
                ],
                onTap: _player.pause,
                onChanged: (index) {
                  if (index != null) _player.selectVariation(index);
                },
              ),
        ],
      ),
      if (_player.frame.comment case final comment? when comment.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(comment)),
      if (_player.error case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_player.record.title)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            Widget board(BoxConstraints bounds) => Center(
              child: SizedBox.square(
                dimension: math.min(bounds.maxWidth, bounds.maxHeight),
                child: _board(),
              ),
            );
            if (constraints.maxWidth >= 600 &&
                constraints.maxWidth > constraints.maxHeight * 1.2) {
              return Row(
                children: [
                  Expanded(child: LayoutBuilder(builder: (_, b) => board(b))),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: math.min(320, constraints.maxWidth * .4),
                    child: SingleChildScrollView(child: _controls()),
                  ),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: LayoutBuilder(builder: (_, b) => board(b))),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .48,
                  ),
                  child: SingleChildScrollView(child: _controls()),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
