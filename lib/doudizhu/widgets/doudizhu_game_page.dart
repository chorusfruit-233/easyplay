import 'dart:async';
import 'package:flutter/material.dart';
import '../doudizhu.dart';
import '../doudizhu_match_controller.dart';
import 'doudizhu_hand.dart';
import 'doudizhu_card.dart';
import 'bidding_panel.dart';

class DouDizhuGamePage extends StatefulWidget {
  const DouDizhuGamePage({super.key, required this.controller});
  final DouDizhuMatchController controller;
  @override
  State<DouDizhuGamePage> createState() => _DouDizhuGamePageState();
}

class _DouDizhuGamePageState extends State<DouDizhuGamePage> {
  final _selected = <int>{};
  bool _hinting = false;
  String? _feedback;
  int _revision = -1;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_revision != widget.controller.revision) {
        _selected.clear();
        _feedback = null;
        _revision = widget.controller.revision;
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _act(String action, [Map<String, Object?> data = const {}]) {
    try {
      widget.controller.act(action, data);
      setState(() {
        _selected.clear();
        _feedback = null;
      });
    } catch (e) {
      setState(
        () => _feedback = e is StateError ? e.message.toString() : '操作失败',
      );
    }
  }

  Future<void> _hint() async {
    final revision = widget.controller.revision;
    setState(() => _hinting = true);
    try {
      final ids = await widget.controller.hint();
      if (!mounted || revision != widget.controller.revision) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(ids);
        _feedback = ids.isEmpty ? '没有合适的出牌，可以不要' : '已选中推荐出牌';
      });
    } finally {
      if (mounted) setState(() => _hinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller,
        state = controller.state,
        view = controller.view;
    final colors = Theme.of(context).colorScheme;
    if (state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final seat = view?.seat ?? state.turn;
    final active =
        !controller.covered && view != null && view.isTurn && controller.canAct;
    final finished = state.phase == DouDizhuPhase.finished;
    final status = finished
        ? '${state.winner == DouDizhuTeam.landlord ? '地主' : '农民'}获胜'
        : state.phase == DouDizhuPhase.bidding
        ? '${state.turn.label}叫分 · 当前最高 ${state.highestBid} 分'
        : '${state.turn.label}${state.trick.seat == null ? '领出' : '出牌'}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('斗地主'),
        actions: [
          IconButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('经典三人斗地主'),
                content: const SingleChildScrollView(
                  child: Text(
                    '54 张牌，每人 17 张，地主取得 3 张底牌并先出。按顺序叫 1–3 分，必须超过当前最高分；全员不叫重新发牌。\n\n'
                    '地主出完则地主胜，任意农民出完则两名农民共同获胜。领出不能不要，连续两人不要后由上一出牌者重新领出。\n\n'
                    '顺子、连对和飞机主体不能包含 2 或王。飞机单翅膀须为不同点数且不能同时带双王；对翅膀须为不同点数的对子。四带二单可带一对，不能带双王；四带两对须为两个不同点数的对子。炸弹压普通牌，王炸最大。\n\n'
                    '熟人房间依赖房主可信；房主保留完整发牌状态，其他玩家仅接收自己的牌。结束后不保存历史牌谱。',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            for (final other in PlayerSeat.values.where(
                              (s) => s != seat,
                            ))
                              Expanded(
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      children: [
                                        Text(
                                          '${other.label}${state.landlord == other
                                              ? ' · 地主'
                                              : state.landlord != null
                                              ? ' · 农民'
                                              : ''}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '剩余 ${state.counts[other.index]} 张${state.bids[other.index] != null ? ' · 叫分 ${state.bids[other.index]}' : ''}',
                                        ),
                                        if (state.turn == other && !finished)
                                          const Text('轮到此玩家'),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (state.bottom.isNotEmpty)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('底牌  '),
                              for (final id in state.bottom)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: DouDizhuCard(
                                    card: PlayingCard(id),
                                    small: true,
                                  ),
                                ),
                            ],
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('底牌未公开  '),
                              for (var i = 0; i < 3; i++)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: DouDizhuCard(small: true),
                                ),
                            ],
                          ),
                        const SizedBox(height: 18),
                        Text(
                          status,
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        if (state.trick.seat != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            '${state.trick.seat!.label} · ${classifyPlay(state.trick.cardIds.map(PlayingCard.new).toList())?.type.label ?? ''}${state.trick.passes > 0 ? ' · 一人不要' : ''}',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final id in state.trick.cardIds)
                                DouDizhuCard(
                                  card: PlayingCard(id),
                                  small: true,
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        if (!controller.canAct) ...[
                          Text(
                            controller.error ?? '等待离线玩家恢复连接',
                            style: TextStyle(color: colors.error),
                          ),
                          if (controller.replica?.reconnect != null)
                            TextButton(
                              onPressed: () async {
                                try {
                                  await controller.replica!.reconnect!();
                                } catch (_) {
                                  if (mounted) {
                                    setState(() => _feedback = '重连失败，请返回房间重试');
                                  }
                                }
                              },
                              child: const Text('重新连接'),
                            )
                          else
                            const Text('返回房间可重新交换邀请'),
                        ],
                        if (controller.covered)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  const Icon(Icons.lock_outline, size: 40),
                                  const SizedBox(height: 12),
                                  Text(
                                    '请把设备交给${state.turn.label}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const Text('其他玩家请移开视线'),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: controller.reveal,
                                    child: const Text('已接过设备，查看手牌'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          if (state.phase == DouDizhuPhase.bidding)
                            BiddingPanel(
                              highest: state.highestBid,
                              enabled: active,
                              onBid: (n) => _act('bid', {'score': n}),
                            ),
                          if (state.phase == DouDizhuPhase.playing)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                OutlinedButton(
                                  onPressed: active && !_hinting ? _hint : null,
                                  child: Text(_hinting ? '思考中…' : '提示'),
                                ),
                                TextButton(
                                  onPressed: _selected.isEmpty
                                      ? null
                                      : () => setState(_selected.clear),
                                  child: const Text('清空'),
                                ),
                                OutlinedButton(
                                  onPressed: active && state.trick.seat != null
                                      ? () => _act('pass')
                                      : null,
                                  child: const Text('不要'),
                                ),
                                FilledButton(
                                  onPressed: active && _selected.isNotEmpty
                                      ? () => _act('play', {
                                          'cards': _selected.toList(),
                                        })
                                      : null,
                                  child: const Text('出牌'),
                                ),
                              ],
                            ),
                          if (finished) ...[
                            FilledButton(
                              onPressed: () => _act('rematch'),
                              child: const Text('再来一局'),
                            ),
                            if (!controller.hotseat)
                              Text(
                                '已确认 ${controller.replica!.rematch.length} 人，等待其他玩家确认',
                              ),
                          ],
                          const SizedBox(height: 12),
                          if (_feedback != null || controller.error != null)
                            Text(
                              _feedback ?? controller.error!,
                              style: TextStyle(color: colors.error),
                            ),
                          if (view != null) ...[
                            Text(
                              '${seat.label}${state.landlord == seat
                                  ? ' · 地主'
                                  : state.landlord != null
                                  ? ' · 农民'
                                  : ''} · ${view.hand.length} 张',
                            ),
                            const SizedBox(height: 8),
                            DouDizhuHand(
                              ids: view.hand,
                              selected: _selected,
                              enabled: active,
                              onToggle: (id) => setState(() {
                                if (!_selected.add(id)) _selected.remove(id);
                              }),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
