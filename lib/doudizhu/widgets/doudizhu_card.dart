import 'package:flutter/material.dart';
import '../doudizhu_model.dart';

class DouDizhuCard extends StatelessWidget {
  const DouDizhuCard({
    super.key,
    this.card,
    this.selected = false,
    this.small = false,
  });
  final PlayingCard? card;
  final bool selected, small;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: small ? 42 : 58,
      height: small ? 62 : 90,
      padding: const EdgeInsets.all(5),
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
                  height: small ? 20 : 28,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: Text(
                      card!.label,
                      style: TextStyle(
                        fontSize: card!.rank >= 16
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
                Text(
                  card!.symbol,
                  style: TextStyle(
                    fontSize: small ? 16 : 22,
                    color: card!.red ? colors.error : colors.onSurface,
                  ),
                ),
              ],
            ),
    );
  }
}
