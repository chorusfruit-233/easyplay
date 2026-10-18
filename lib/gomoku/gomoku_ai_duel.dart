import 'dart:async';

import '../ai/ai_duel_config.dart';
import '../ai/ai_duel_controller.dart';
import '../game_session.dart' show Side;
import 'gomoku_ai_level.dart';
import 'gomoku_player.dart';
import 'engine/rapfi_player.dart';
import 'gomoku_session.dart';
import 'gomoku_storage.dart';

class GomokuAiDuelController extends AiDuelController<GomokuAction> {
  GomokuAiDuelController({
    required this.session,
    required this.config,
    GomokuPlayer? ai,
    String? recordId,
    DateTime? createdAt,
    super.initiallyPaused,
    super.moveInterval,
  }) : _ai = ai ?? RapfiPlayer(),
       createdAt = createdAt ?? DateTime.now().toUtc(),
       recordId =
           recordId ?? 'gomoku-duel-${DateTime.now().microsecondsSinceEpoch}';

  final GomokuSession session;
  final AiDuelConfig<GomokuAiLevel> config;
  final GomokuPlayer _ai;
  String recordId;
  DateTime createdAt;

  @override
  Side get turn => session.actor;
  @override
  int get revision => session.revision;
  @override
  int get moveCount => session.moves.length;
  @override
  bool get gameOver => session.gameOver;
  @override
  String get resultLabel => session.resultLabel;

  @override
  Future<GomokuAction?> search() async {
    final action = await _ai.decide(session, level: config.levelFor(turn));
    if (action == null && _ai.failureReason != null) {
      throw StateError(_ai.failureReason!);
    }
    return action;
  }

  @override
  void cancelSearch() => _ai.cancel();
  @override
  void dispose() {
    super.dispose();
    unawaited(_ai.dispose());
  }

  @override
  bool applyMove(GomokuAction move) => session.applyAction(move);
  @override
  bool undoPosition() => session.undo();

  @override
  void resetPosition() {
    session.reset();
    createdAt = DateTime.now().toUtc();
    recordId = 'gomoku-duel-${createdAt.microsecondsSinceEpoch}';
  }

  @override
  Future<void> savePosition() => GomokuStorage.save(
    GomokuRecord(
      id: recordId,
      createdAt: createdAt,
      session: session,
      aiDuel: config,
    ),
  );
}
