import 'package:flutter/material.dart';
import '../doudizhu_model.dart';

class DouDizhuCard extends StatelessWidget {
  const DouDizhuCard({
    super.key,
    this.card,
    this.selected = false,
    this.small = false,
    this.compact = false,
  });
  final PlayingCard? card;
  final bool selected, small, compact;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final symbol = Text(
      compact && card != null && card!.rank >= 16 ? '王' : card?.symbol ?? '',
      style: TextStyle(
        fontSize: compact
            ? 10
            : small
            ? 16
            : 22,
        color: card?.red == true ? colors.error : colors.onSurface,
      ),
    );
    return Container(
      width: compact
          ? 24
          : small
          ? 42
          : 58,
      height: compact
          ? 34
          : small
          ? 62
          : 90,
      padding: EdgeInsets.all(compact ? 3 : 5),
      decoration: BoxDecoration(
        color: card == null
            ? colors.primaryContainer
            : selected
            ? colors.secondaryContainer
            : colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(color: colors.shadow.withValues(alpha: .12), blurRadius: 3),
        ],
      ),
      child: card == null
          ? Icon(Icons.style, color: colors.onPrimaryContainer)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: compact
                      ? 13
                      : small
                      ? 20
                      : 28,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: Text(
                      compact && card!.rank >= 16
                          ? (card!.rank == 16 ? '小' : '大')
                          : card!.label,
                      style: TextStyle(
                        fontSize: compact
                            ? 10
                            : card!.rank >= 16
                            ? 12
                            : small
                            ? 16
                            : 20,
                        fontWeight: FontWeight.bold,
                        color: card!.red ? colors.error : colors.onSurface,
                      ),
                    ),
                  ),
                ),
                if (compact)
                  SizedBox(
                    height: 12,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: symbol,
                    ),
                  ),
                if (!compact) symbol,
              ],
            ),
    );
  }
}
