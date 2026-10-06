import '../../ui/app_layout.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../chess.dart';
import '../engine/chess_engine.dart';
import 'chess_game_page.dart';

class ChessAiSettingsPage extends StatefulWidget {
  const ChessAiSettingsPage({super.key});
  @override
  State<ChessAiSettingsPage> createState() => _ChessAiSettingsPageState();
}

class _ChessAiSettingsPageState extends State<ChessAiSettingsPage> {
  String _side = 'white';
  ChessAiLevel _level = ChessAiLevel.normal;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 对战')),
    body: AppPageList(
      children: [
        const Text('执棋'),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'white', label: Text('白方')),
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
            for (final level in ChessAiLevel.values)
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
                ? (Random().nextBool() ? Side.white : Side.black)
                : _side == 'white'
                ? Side.white
                : Side.black;
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ChessGamePage.ai(humanSide: side, level: _level),
              ),
            );
          },
          child: const Text('开始对局'),
        ),
      ],
    ),
  );
}
