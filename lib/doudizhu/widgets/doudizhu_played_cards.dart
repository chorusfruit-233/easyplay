import 'dart:math';

import 'package:flutter/material.dart';

import '../doudizhu_model.dart';
import '../doudizhu_rules.dart';
import '../doudizhu_table.dart';
import 'doudizhu_card.dart';

/// Read-only cards beside a player, separate from selectable private cards.
class DouDizhuPlayedCards extends StatelessWidget {
  const DouDizhuPlayedCards({
    super.key,
    required this.seat,
    required this.play,
    required this.complete,
    required this.strongest,
  });

  final PlayerSeat seat;
  final DouDizhuSeatPlay play;
  final bool complete, strongest;

  @override
  Widget build(BuildContext context) {
    final cards = PlayingCard.sorted(play.cards.map(PlayingCard.new));
    final pattern = classifyPlay(cards)?.type.label;
    final label =
        '${seat.label}${complete ? '上轮' : '本轮'}出牌：'
        '${cards.map((c) => '${c.symbol}${c.label}').join('、')}'
        '${play.passed ? '，不要' : ''}';
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: strongest && !complete
              ? colors.secondaryContainer
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: strongest && !complete
                ? colors.primary
                : colors.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${complete
                  ? '上轮'
                  : strongest
                  ? '当前'
                  : '本轮'}'
              '${pattern == null ? '' : ' · $pattern'}'
              '${play.passed ? ' · 不要' : ''}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (cards.isNotEmpty) ...[
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Leave both digits of "10" visible under overlapping cards.
                  const width = 24.0, advance = 16.0, height = 34.0;
                  final perRow = max(
                    1,
                    ((constraints.maxWidth - width) / advance).floor() + 1,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      for (var start = 0; start < cards.length; start += perRow)
                        SizedBox(
                          width:
                              width +
                              (min(perRow, cards.length - start) - 1) * advance,
                          height: height,
                          child: Stack(
                            children: [
                              for (
                                var i = 0;
                                i < min(perRow, cards.length - start);
                                i++
                              )
                                Positioned(
                                  left: i * advance,
                                  child: DouDizhuCard(
                                    key: ValueKey(
                                      'played-card-${seat.index}-${cards[start + i].id}',
                                    ),
                                    card: cards[start + i],
                                    compact: true,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
