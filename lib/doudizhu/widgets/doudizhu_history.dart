import 'package:flutter/material.dart';
import '../doudizhu.dart';
import '../doudizhu_match_controller.dart';
import 'doudizhu_card.dart';

class DouDizhuHistory extends StatelessWidget {
  const DouDizhuHistory({super.key, required this.controller});
  final DouDizhuMatchController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.state;
      final history = state?.history;
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('历史出牌（本局）')),
                  IconButton(
                    tooltip: '关闭历史出牌',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: history == null || history.isEmpty
                  ? Center(
                      child: Text(history == null ? '房主版本不支持历史出牌' : '本局还没有出牌'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        // Latest actions first; numbers retain chronological order.
                        final number = history.length - index;
                        final play = history[number - 1];
                        final pattern = classifyPlay(
                          play.cardIds.map(PlayingCard.new).toList(),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$number · ${play.seat.label} · '
                                '${play.seat == state!.landlord ? '地主' : '农民'} · '
                                '${play.cardIds.isEmpty ? '不要' : pattern?.type.label ?? '出牌'}',
                              ),
                              if (play.cardIds.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    for (final card in PlayingCard.sorted(
                                      play.cardIds.map(PlayingCard.new),
                                    ))
                                      DouDizhuCard(card: card, small: true),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
