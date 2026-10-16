import 'package:flutter/material.dart';

import '../ai_duel_config.dart';

Future<AiDuelConfig<L>?> showAiDuelSetup<L extends Enum>({
  required BuildContext context,
  required List<L> levels,
  required L initialLevel,
  required String Function(L) label,
}) {
  var black = initialLevel;
  var white = initialLevel;
  return showDialog<AiDuelConfig<L>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('AI 对抗'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('两名 AI 自动对弈，你可以暂停或单步观战。'),
              const SizedBox(height: 16),
              for (final isBlack in [true, false]) ...[
                DropdownButtonFormField<L>(
                  key: ValueKey(
                    isBlack ? 'duel-black-level' : 'duel-white-level',
                  ),
                  initialValue: isBlack ? black : white,
                  decoration: InputDecoration(
                    labelText: isBlack ? '黑方 AI 难度' : '白方 AI 难度',
                  ),
                  items: [
                    for (final level in levels)
                      DropdownMenuItem(value: level, child: Text(label(level))),
                  ],
                  onChanged: (value) => update(() {
                    if (value == null) return;
                    if (isBlack) {
                      black = value;
                    } else {
                      white = value;
                    }
                  }),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              AiDuelConfig(blackLevel: black, whiteLevel: white),
            ),
            child: const Text('开始观战'),
          ),
        ],
      ),
    ),
  );
}
