import 'package:flutter/material.dart';

import '../../ai/ai_duel_config.dart';
import '../../ai/widgets/ai_duel_page.dart';
import '../draughts_ai_duel.dart';
import '../draughts_ai_level.dart';
import '../draughts_move.dart';
import '../draughts_session.dart';
import '../draughts_variant.dart';
import 'draughts_board.dart';
import 'draughts_match_layout.dart';

class DraughtsAiDuelPage extends StatefulWidget {
  const DraughtsAiDuelPage({
    super.key,
    required this.session,
    required this.config,
    this.recordId,
    this.createdAt,
    this.initiallyPaused = false,
  });

  final DraughtsSession session;
  final AiDuelConfig<DraughtsAiLevel> config;
  final String? recordId;
  final DateTime? createdAt;
  final bool initiallyPaused;

  @override
  State<DraughtsAiDuelPage> createState() => _DraughtsAiDuelPageState();
}

class _DraughtsAiDuelPageState extends State<DraughtsAiDuelPage> {
  late final _controller = DraughtsAiDuelController(
    session: widget.session,
    config: widget.config,
    recordId: widget.recordId,
    createdAt: widget.createdAt,
    initiallyPaused: widget.initiallyPaused,
  );

  @override
  Widget build(BuildContext context) => AiDuelPage<DraughtsMove>(
    controller: _controller,
    title: '跳棋',
    rules: _controller.session.variant.label,
    blackLevel: widget.config.blackLevel.label,
    whiteLevel: widget.config.whiteLevel.label,
    boardBuilder: (_) =>
        DraughtsBoard(session: _controller.session, onCell: (_) {}),
    layoutBuilder: (header, board, footer) => DraughtsMatchLayout(
      compactLandscape: true,
      header: header,
      board: board,
      footer: footer,
    ),
  );
}
