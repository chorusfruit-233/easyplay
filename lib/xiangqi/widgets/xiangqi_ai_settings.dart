import '../../ui/app_layout.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../xiangqi.dart';
import '../engine/xiangqi_engine.dart';
import 'xiangqi_game_page.dart';

class XiangqiAiSettingsPage extends StatefulWidget {
  const XiangqiAiSettingsPage({super.key});
  @override
  State<XiangqiAiSettingsPage> createState() => _XiangqiAiSettingsPageState();
}

class _XiangqiAiSettingsPageState extends State<XiangqiAiSettingsPage> {
  String _side = 'red';
  XiangqiAiLevel _level = XiangqiAiLevel.normal;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 对战')),
    body: AppPageList(
      children: [
        const Text('执棋'),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'red', label: Text('红方')),
            ButtonSegment(value: 'black', label: Text('黑方')),
            ButtonSegment(value: 'random', label: Text('随机')),
          ],
          selected: {_side},
          onSelectionChanged: (value) => setState(() => _side = value.single),
        ),
        const SizedBox(height: 24),
        const Text('难度'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final level in XiangqiAiLevel.values)
              ChoiceChip(
                label: Text(level.label),
                selected: _level == level,
                onSelected: (_) => setState(() => _level = level),
              ),
          ],
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () {
            final side = _side == 'random'
                ? (Random().nextBool() ? XiangqiSide.red : XiangqiSide.black)
                : _side == 'red'
                ? XiangqiSide.red
                : XiangqiSide.black;
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    XiangqiGamePage.ai(humanSide: side, level: _level),
              ),
            );
          },
          child: const Text('开始对局'),
        ),
      ],
    ),
  );
}
