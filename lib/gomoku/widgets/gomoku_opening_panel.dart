import 'package:flutter/material.dart';

import '../gomoku_session.dart';

class GomokuOpeningPanel extends StatelessWidget {
  const GomokuOpeningPanel({
    super.key,
    required this.session,
    required this.enabled,
    required this.onExchange,
  });
  final GomokuSession session;
  final bool enabled;
  final ValueChanged<bool> onExchange;

  @override
  Widget build(BuildContext context) {
    if (!session.variant.competitive || session.gameOver) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(
            session.phaseLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (session.phase != GomokuPhase.normal)
            Text(
              session.phaseHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (session.phase == GomokuPhase.exchange)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: enabled ? () => onExchange(true) : null,
                  child: const Text('交换执棋'),
                ),
                OutlinedButton(
                  onPressed: enabled ? () => onExchange(false) : null,
                  child: const Text('不交换'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
