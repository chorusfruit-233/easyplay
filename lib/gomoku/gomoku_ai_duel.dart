import '../ai/ai_duel_config.dart';
import '../ai/ai_duel_controller.dart';
import '../game_session.dart' show Cell, Side;
import 'gomoku_ai.dart';
import 'gomoku_session.dart';
import 'gomoku_storage.dart';

class GomokuAiDuelController extends AiDuelController<Cell> {
  GomokuAiDuelController({
    required this.session,
    required this.config,
    GomokuAi? ai,
    String? recordId,
    DateTime? createdAt,
    super.initiallyPaused,
    super.moveInterval,
  }) : _ai = ai ?? GomokuAi(),
       createdAt = createdAt ?? DateTime.now().toUtc(),
       recordId =
           recordId ?? 'gomoku-duel-${DateTime.now().microsecondsSinceEpoch}';

  final GomokuSession session;
  final AiDuelConfig<GomokuAiLevel> config;
  final GomokuAi _ai;
  String recordId;
  DateTime createdAt;

  @override
  Side get turn => session.turn;
  @override
  int get revision => session.revision;
  @override
  int get moveCount => session.moves.length;
  @override
  bool get gameOver => session.gameOver;
  @override
  String get resultLabel => session.resultLabel;

  @override
  Future<Cell?> search() async =>
      (await _ai.search(session, level: config.levelFor(turn)))?.cell;

  @override
  void cancelSearch() => _ai.cancel();
  @override
  bool applyMove(Cell move) => session.place(move);
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
