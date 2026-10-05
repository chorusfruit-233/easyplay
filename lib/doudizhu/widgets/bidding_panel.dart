import 'package:flutter/material.dart';

class BiddingPanel extends StatelessWidget {
  const BiddingPanel({
    super.key,
    required this.highest,
    required this.enabled,
    required this.onBid,
  });
  final int highest;
  final bool enabled;
  final ValueChanged<int> onBid;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.center,
    children: [
      for (final score in [0, 1, 2, 3])
        FilledButton.tonal(
          onPressed: enabled && (score == 0 || score > highest)
              ? () => onBid(score)
              : null,
          child: Text(score == 0 ? '不叫' : '叫 $score 分'),
        ),
    ],
  );
}
