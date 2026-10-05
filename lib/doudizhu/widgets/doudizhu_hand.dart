import 'dart:math';
import 'package:flutter/material.dart';
import '../doudizhu_model.dart';
import 'doudizhu_card.dart';

class DouDizhuHand extends StatelessWidget {
  const DouDizhuHand({
    super.key,
    required this.ids,
    required this.selected,
    required this.onToggle,
    this.enabled = true,
  });
  final List<int> ids;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final cards = PlayingCard.sorted(ids.map(PlayingCard.new));
    return LayoutBuilder(
      builder: (context, c) {
        final rows = c.maxWidth < 480 && cards.length > 10
            ? [
                cards.take((cards.length + 1) ~/ 2).toList(),
                cards.skip((cards.length + 1) ~/ 2).toList(),
              ]
            : [cards];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < rows.length; row++)
              _HandRow(
                key: ValueKey(row),
                cards: rows[row],
                selected: selected,
                onToggle: onToggle,
                enabled: enabled,
              ),
          ],
        );
      },
    );
  }
}

class _HandRow extends StatefulWidget {
  const _HandRow({
    super.key,
    required this.cards,
    required this.selected,
    required this.onToggle,
    required this.enabled,
  });
  final List<PlayingCard> cards;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final bool enabled;
  @override
  State<_HandRow> createState() => _HandRowState();
}

class _HandRowState extends State<_HandRow> {
  final _dragged = <int>{};
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cards = widget.cards;
      final step = cards.length <= 1
          ? 28.0
          : max(12.0, min(36.0, (c.maxWidth - 58) / (cards.length - 1)));
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(c.maxWidth, 58 + step * max(0, cards.length - 1)),
          height: 114,
          child: GestureDetector(
            onHorizontalDragStart: widget.enabled
                ? (_) => _dragged.clear()
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (d) {
                    if (cards.isEmpty) return;
                    final index = (d.localPosition.dx / step).floor().clamp(
                      0,
                      cards.length - 1,
                    );
                    if (_dragged.add(cards[index].id)) {
                      widget.onToggle(cards[index].id);
                    }
                  }
                : null,
            child: Stack(
              children: [
                for (var i = 0; i < cards.length; i++)
                  Positioned(
                    left: i * step,
                    top: widget.selected.contains(cards[i].id) ? 0 : 18,
                    child: Semantics(
                      label: '${cards[i].symbol}${cards[i].label}',
                      selected: widget.selected.contains(cards[i].id),
                      button: true,
                      child: GestureDetector(
                        onTap: widget.enabled
                            ? () => widget.onToggle(cards[i].id)
                            : null,
                        child: DouDizhuCard(
                          key: ValueKey('card-${cards[i].id}'),
                          card: cards[i],
                          selected: widget.selected.contains(cards[i].id),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
