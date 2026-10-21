import 'package:flutter/material.dart';

import '../battleship.dart';
import '../battleship_match_controller.dart';
import 'battleship_board.dart';

class BattleshipGamePage extends StatefulWidget {
  const BattleshipGamePage({super.key, required this.controller});
  final BattleshipMatchController controller;

  @override
  State<BattleshipGamePage> createState() => _BattleshipGamePageState();
}

class _BattleshipGamePageState extends State<BattleshipGamePage>
    with WidgetsBindingObserver {
  ShipType _ship = ShipType.carrier;
  ShipDirection _direction = ShipDirection.horizontal;
  int? _start, _target;
  BattleshipSeat? _seat;
  BattleshipPhase? _phase;
  String? _feedback;
  ({ShipPlacement placement, int revision, BattleshipSeat seat})?
  _pendingPlacement;
  BattleshipMatchController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    controller.setActive(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    _seat = controller.view?.seat;
    _phase = controller.phase;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setActive(state == AppLifecycleState.resumed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      final view = controller.view;
      if (_seat != view?.seat || _phase != controller.phase) {
        _start = _target = null;
        _ship = ShipType.carrier;
        _feedback = null;
        _pendingPlacement = null;
      }
      final pending = _pendingPlacement;
      if (pending != null) {
        if (view == null ||
            controller.error != null ||
            view.seat != pending.seat) {
          _pendingPlacement = null;
        } else if (controller.revision > pending.revision &&
            view.ownFleet.contains(pending.placement)) {
          _pendingPlacement = null;
          final next = ShipType.values
              .where((ship) => !view.ownFleet.any((p) => p.ship == ship))
              .firstOrNull;
          if (next != null) _ship = next;
          _start = null;
        }
      }
      if (_target != null && !(view?.canFire(_target!) ?? false)) {
        _target = null;
      }
      _seat = view?.seat;
      _phase = controller.phase;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    controller.setActive(false);
    super.dispose();
  }

  void _act(
    VoidCallback action, {
    bool clearSelection = true,
    bool preservePendingPlacement = false,
  }) {
    if (!preservePendingPlacement) _pendingPlacement = null;
    try {
      action();
      setState(() {
        _feedback = null;
        if (clearSelection) _start = _target = null;
      });
    } catch (error) {
      setState(() {
        _pendingPlacement = null;
        _feedback = error is StateError
            ? error.message.toString()
            : error is ArgumentError
            ? error.message?.toString() ?? '请检查选择的位置'
            : '操作未完成，请重试';
      });
    }
  }

  void _place() {
    final view = controller.view;
    if (view == null || _start == null) return;
    _act(() {
      final placement = ShipPlacement(_ship, _start!, _direction);
      _pendingPlacement = (
        placement: placement,
        revision: controller.revision,
        seat: view.seat,
      );
      controller.place(placement);
    }, preservePendingPlacement: true);
  }

  Future<void> _resign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认认输？'),
        content: const Text('认输后结束本局，并公开双方舰队。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续对局'),
          ),
          FilledButton(
            key: const ValueKey('battleship-confirm-resign'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('认输'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _act(controller.resign);
  }

  void _rules() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('经典海战棋 Battleship'),
      content: const SingleChildScrollView(
        child: Text(
          '双方各有一片 10×10 海域，秘密布置 5 艘舰船：航母 5 格、战列舰 4 格、巡洋舰 3 格、潜艇 3 格、驱逐舰 2 格，共 17 格。\n\n'
          '舰船只能横向或纵向笔直放置，不能越界或重叠，可以相邻。双方确认后锁定舰队，不能再移动。\n\n'
          '每回合选择敌方一个未攻击的位置，再按「确认开火」。无论命中与否，均轮到对方。命中舰船全部格子即击沉，击沉全部 5 艘舰船获胜。\n\n'
          'AI 仅根据已知开火结果侦察。联机对手只接收自己的舰队与公开结果；房主保存权威对局，熟人房间需要信任房主。对局仅保留在内存，退出后不保存。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  void _history() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final shots = controller.shots;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '开火记录 · ${shots.length} 次',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭开火记录',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: shots.isEmpty
                    ? const Center(child: Text('本局尚未开火'))
                    : ListView.builder(
                        itemCount: shots.length,
                        itemBuilder: (context, index) {
                          final shot = shots[shots.length - index - 1];
                          return ListTile(
                            leading: Text('${shots.length - index}'),
                            title: Text(
                              '${shot.attacker.label} · ${battleshipCoordinate(shot.cell)} · ${shot.outcome.label}',
                            ),
                            subtitle: shot.sunkShip == null
                                ? null
                                : Text('击沉${shot.sunkShip!.label}'),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );

  String _status(BattleshipPlayerView view) => switch (view.phase) {
    BattleshipPhase.placement =>
      view.ownReady ? '舰队已锁定，等待对手准备' : '${view.seat.label} · 布置舰队',
    BattleshipPhase.playing =>
      controller.thinking
          ? 'AI 正在侦察…'
          : view.isTurn
          ? '轮到你开火'
          : '等待${view.turn.label}开火',
    BattleshipPhase.finished => '${view.winner!.label}获胜',
  };

  Widget _latestShot(List<BattleshipShot> shots) {
    if (shots.isEmpty) return const SizedBox.shrink();
    final shot = shots.last;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '${shot.attacker.label} → ${battleshipCoordinate(shot.cell)} · ${shot.outcome.label}${shot.sunkShip == null ? '' : shot.sunkShip!.label}',
        key: const ValueKey('battleship-last-shot'),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _handoff() => Card(
    key: const ValueKey('battleship-handoff'),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, size: 44),
          const SizedBox(height: 16),
          Text(
            '请把设备交给${controller.handoffSeat.label}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('其他玩家请移开视线，舰队位置尚未显示。', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('battleship-reveal'),
            onPressed: controller.reveal,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('已接过设备，查看海域'),
          ),
        ],
      ),
    ),
  );

  List<int> _previewCells() {
    final start = _start;
    if (start == null) return const [];
    return [
      for (var i = 0; i < _ship.length; i++)
        if (_direction == ShipDirection.horizontal
            ? start % 10 + i < 10
            : start ~/ 10 + i < 10)
          start + i * (_direction == ShipDirection.horizontal ? 1 : 10),
    ];
  }

  Widget _placement(BattleshipPlayerView view) {
    final enabled = controller.canAct && !view.ownReady;
    final valid =
        _start != null &&
        canPlaceBattleshipAt(view.ownFleet, _ship, _start!, _direction);
    final placed = view.ownFleet.map((placement) => placement.ship).toSet();
    final canReady = enabled && placed.length == ShipType.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '舰队 ${placed.length}/5 · ${view.enemyReady ? '对手已就绪' : '等待对手布阵'}',
          key: const ValueKey('battleship-placement-status'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        if (!view.ownReady) ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ship in ShipType.values)
                ChoiceChip(
                  key: ValueKey('battleship-ship-${ship.name}'),
                  selected: ship == _ship,
                  avatar: placed.contains(ship)
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  label: Text('${ship.label} · ${ship.length} 格'),
                  onSelected: enabled
                      ? (_) => setState(() {
                          _pendingPlacement = null;
                          _ship = ship;
                          final current = view.ownFleet
                              .where((p) => p.ship == ship)
                              .firstOrNull;
                          _start = current?.start;
                          if (current != null) _direction = current.direction;
                          _feedback = null;
                        })
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('选择舰船，点击海域指定起点，再确认放置。', textAlign: TextAlign.center),
          const SizedBox(height: 8),
        ],
        BattleshipBoard(
          id: 'own',
          label: '我方海域',
          fleet: view.ownFleet,
          preview: enabled ? _previewCells() : const [],
          previewValid: valid,
          selected: enabled ? _start : null,
          onCell: enabled
              ? (cell) => setState(() {
                  _pendingPlacement = null;
                  _start = cell;
                  _feedback = null;
                })
              : null,
        ),
        if (!view.ownReady) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('battleship-rotate'),
                onPressed: enabled
                    ? () => setState(() {
                        _pendingPlacement = null;
                        _direction = _direction == ShipDirection.horizontal
                            ? ShipDirection.vertical
                            : ShipDirection.horizontal;
                      })
                    : null,
                icon: const Icon(Icons.rotate_90_degrees_cw),
                label: Text(
                  _direction == ShipDirection.horizontal ? '横向' : '纵向',
                ),
              ),
              FilledButton(
                key: const ValueKey('battleship-place'),
                onPressed: enabled && valid ? _place : null,
                child: Text('放置${_ship.label}'),
              ),
              if (placed.contains(_ship))
                TextButton(
                  key: const ValueKey('battleship-remove'),
                  onPressed: enabled
                      ? () => _act(() => controller.remove(_ship))
                      : null,
                  child: const Text('移除选中舰船'),
                ),
            ],
          ),
          if (_start != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                valid
                    ? '起点 ${battleshipCoordinate(_start!)} · 可放置'
                    : '该位置越界或与其他舰船重叠',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: valid
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('battleship-randomize'),
                onPressed: enabled ? () => _act(controller.randomize) : null,
                icon: const Icon(Icons.shuffle),
                label: const Text('随机布阵'),
              ),
              TextButton(
                key: const ValueKey('battleship-clear'),
                onPressed: enabled && placed.isNotEmpty
                    ? () => _act(controller.clear)
                    : null,
                child: const Text('清空舰队'),
              ),
              FilledButton.icon(
                key: const ValueKey('battleship-ready'),
                onPressed: canReady ? () => _act(controller.ready) : null,
                icon: const Icon(Icons.lock_outline),
                label: const Text('确认舰队'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _targetBoard(BattleshipPlayerView view) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('敌方海域', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      BattleshipBoard(
        id: 'target',
        label: '敌方海域',
        fleet: view.phase == BattleshipPhase.finished
            ? view.enemyFleet
            : const [],
        shots: view.outgoingShots,
        selected: _target,
        canSelect: view.canFire,
        onCell: controller.canAct && view.isTurn
            ? (cell) => setState(() {
                _target = cell;
                _feedback = null;
              })
            : null,
      ),
      const SizedBox(height: 12),
      if (view.phase == BattleshipPhase.playing) ...[
        Text(
          _target == null
              ? '选择一个尚未攻击的位置'
              : '目标 ${battleshipCoordinate(_target!)} · 确认后才会开火',
          key: const ValueKey('battleship-target-label'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _target == null
                  ? null
                  : () => setState(() => _target = null),
              child: const Text('取消选择'),
            ),
            FilledButton.icon(
              key: const ValueKey('battleship-fire'),
              onPressed:
                  controller.canAct && _target != null && view.canFire(_target!)
                  ? () => _act(() => controller.fire(_target!))
                  : null,
              icon: const Icon(Icons.gps_fixed),
              label: const Text('确认开火'),
            ),
          ],
        ),
      ],
    ],
  );

  Widget _ownBoard(BattleshipPlayerView view) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('我方海域', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      BattleshipBoard(
        id: 'own',
        label: '我方海域',
        fleet: view.ownFleet,
        shots: view.incomingShots,
      ),
    ],
  );

  Widget _battle(BattleshipPlayerView view) {
    final outgoing = view.outgoingShots.toList();
    final incoming = view.incomingShots.toList();
    final hits = outgoing.where((s) => s.outcome != ShotOutcome.miss).length;
    final enemySunk = outgoing
        .where((s) => s.outcome == ShotOutcome.sunk)
        .length;
    final ownSunk = incoming.where((s) => s.outcome == ShotOutcome.sunk).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '命中 $hits/17 · 击沉敌舰 $enemySunk/5 · 我方剩余 ${5 - ownSunk} 艘',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 680
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _targetBoard(view)),
                    const SizedBox(width: 20),
                    Expanded(child: _ownBoard(view)),
                  ],
                )
              : Column(
                  children: [
                    _targetBoard(view),
                    const SizedBox(height: 24),
                    _ownBoard(view),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [Text('● 未命中'), Text('× 命中'), Text('▣ 击沉')],
        ),
        if (view.phase == BattleshipPhase.finished) ...[
          const SizedBox(height: 12),
          const Text('本局结束，双方舰队已公开。', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.icon(
              key: const ValueKey('battleship-rematch'),
              onPressed: controller.connected && !controller.rematchPending
                  ? () => _act(controller.rematch)
                  : null,
              icon: const Icon(Icons.replay),
              label: Text(controller.rematchPending ? '已请求，等待对手确认' : '再来一局'),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = controller.view;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('battleship-game'),
      appBar: AppBar(
        title: const Text('海战棋'),
        actions: [
          IconButton(
            tooltip: '开火记录',
            onPressed: _history,
            icon: const Icon(Icons.history),
          ),
          if (view?.phase == BattleshipPhase.playing)
            IconButton(
              tooltip: '认输',
              onPressed: controller.canAct && view!.isTurn ? _resign : null,
              icon: const Icon(Icons.flag_outlined),
            ),
          IconButton(
            tooltip: '海战棋规则',
            onPressed: _rules,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!controller.connected) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              controller.error ?? '连接中断，对局已暂停',
                              style: TextStyle(color: colors.error),
                            ),
                            if (controller.canReconnect)
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await controller.reconnect();
                                  } catch (_) {
                                    if (mounted) {
                                      setState(
                                        () => _feedback = '重连失败，请返回房间重试',
                                      );
                                    }
                                  }
                                },
                                child: const Text('重新连接'),
                              )
                            else
                              const Text('返回房间可重新交换邀请'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (view != null)
                    Text(
                      _status(view),
                      key: const ValueKey('battleship-status'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  _latestShot(controller.shots),
                  if (_feedback != null || controller.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _feedback ?? controller.error!,
                      key: const ValueKey('battleship-feedback'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error),
                    ),
                    if (controller.thinking && controller.error != null)
                      TextButton(
                        onPressed: controller.retryAi,
                        child: const Text('重试 AI'),
                      ),
                  ],
                  const SizedBox(height: 16),
                  if (controller.covered)
                    _handoff()
                  else if (view == null)
                    const Center(child: CircularProgressIndicator())
                  else if (view.phase == BattleshipPhase.placement)
                    _placement(view)
                  else
                    _battle(view),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
