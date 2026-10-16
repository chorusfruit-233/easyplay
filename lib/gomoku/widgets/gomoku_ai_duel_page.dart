import 'package:flutter/material.dart';

import '../../ai/ai_duel_config.dart';
import '../../ai/widgets/ai_duel_page.dart';
import '../../game_session.dart' show Cell;
import '../gomoku_ai_duel.dart';
import '../gomoku_ai_level.dart';
import '../gomoku_session.dart';
import 'gomoku_board.dart';

class GomokuAiDuelPage extends StatefulWidget {
  const GomokuAiDuelPage({
    super.key,
    required this.session,
    required this.config,
    this.recordId,
    this.createdAt,
    this.initiallyPaused = false,
  });

  final GomokuSession session;
  final AiDuelConfig<GomokuAiLevel> config;
  final String? recordId;
  final DateTime? createdAt;
  final bool initiallyPaused;

  @override
  State<GomokuAiDuelPage> createState() => _GomokuAiDuelPageState();
}

class _GomokuAiDuelPageState extends State<GomokuAiDuelPage> {
  late final _controller = GomokuAiDuelController(
    session: widget.session,
    config: widget.config,
    recordId: widget.recordId,
    createdAt: widget.createdAt,
    initiallyPaused: widget.initiallyPaused,
  );

  @override
  Widget build(BuildContext context) => AiDuelPage<Cell>(
    controller: _controller,
    title: '五子棋',
    rules: _controller.session.variant.label,
    blackLevel: widget.config.blackLevel.label,
    whiteLevel: widget.config.whiteLevel.label,
    boardBuilder: (_) => GomokuBoard(
      session: _controller.session,
      enabled: false,
      onCell: (_) {},
    ),
    layoutBuilder: (header, board, footer) =>
        GomokuMatchLayout(header: header, board: board, footer: footer),
  );
}
