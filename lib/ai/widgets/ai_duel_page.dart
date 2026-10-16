import 'package:flutter/material.dart';

import '../../game_session.dart' show Side, SideX;
import '../ai_duel_controller.dart';

/// Owns the controller for the lifetime of the spectator route.
class AiDuelPage<M> extends StatefulWidget {
  const AiDuelPage({
    super.key,
    required this.controller,
    required this.title,
    required this.rules,
    required this.blackLevel,
    required this.whiteLevel,
    required this.boardBuilder,
    required this.layoutBuilder,
  });

  final AiDuelController<M> controller;
  final String title;
  final String rules;
  final String blackLevel;
  final String whiteLevel;
  final WidgetBuilder boardBuilder;
  final Widget Function(Widget header, Widget board, Widget footer)
  layoutBuilder;

  @override
  State<AiDuelPage<M>> createState() => _AiDuelPageState<M>();
}

class _AiDuelPageState<M> extends State<AiDuelPage<M>>
    with WidgetsBindingObserver {
  AiDuelController<M> get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _controller.setForeground(
      lifecycle == null || lifecycle == AppLifecycleState.resumed,
    );
    _controller.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _controller.setForeground(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _restart() async {
    final wasPaused = _controller.paused;
    _controller.pause();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新开始 AI 对抗？'),
        content: const Text('当前对局保留在历史记录中，新对局沿用双方难度。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重新开始'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted == true) {
      _controller.restart(paused: wasPaused);
    } else if (!wasPaused) {
      _controller.resume();
    }
  }

  Widget _player(Side side, String level) {
    final active = !_controller.gameOver && _controller.turn == side;
    final colors = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        side == Side.black ? Icons.circle : Icons.circle_outlined,
        size: 18,
        color: active ? colors.primary : colors.onSurfaceVariant,
      ),
      label: Text('${side.label} AI · $level'),
      backgroundColor: active ? colors.secondaryContainer : null,
    );
  }

  String get _status {
    if (_controller.gameOver) return _controller.resultLabel;
    if (_controller.error != null) return _controller.error!;
    if (!_controller.foreground) return '应用已挂起';
    if (_controller.thinking) return '${_controller.turn.label} AI 正在思考…';
    if (_controller.paused) return '已暂停 · 轮到${_controller.turn.label} AI';
    return '轮到${_controller.turn.label} AI';
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _controller.stop();
    },
    child: Scaffold(
      appBar: AppBar(title: Text('${widget.title} · AI 对抗')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => widget.layoutBuilder(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.rules,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _player(Side.black, widget.blackLevel),
                    _player(Side.white, widget.whiteLevel),
                  ],
                ),
                Text(_status, style: Theme.of(context).textTheme.titleMedium),
                Text('第 ${_controller.moveCount} 手 · 观战模式'),
                if (_controller.saveError != null) Text(_controller.saveError!),
                const SizedBox(height: 8),
              ],
            ),
            IgnorePointer(child: widget.boardBuilder(context)),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _controller.gameOver
                        ? null
                        : _controller.paused
                        ? _controller.resume
                        : _controller.pause,
                    icon: Icon(
                      _controller.paused ? Icons.play_arrow : Icons.pause,
                    ),
                    label: Text(_controller.paused ? '继续' : '暂停'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _controller.canStep ? _controller.step : null,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('单步'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _controller.moveCount > 0
                        ? _controller.undo
                        : null,
                    icon: const Icon(Icons.undo),
                    label: const Text('悔棋'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _restart,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重开'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
