import '../ai/ai_duel_config.dart';
import '../ai/ai_duel_controller.dart';
import '../game_session.dart' show Side, SideX;
import 'draughts_ai.dart';
import 'draughts_ai_level.dart';
import 'draughts_move.dart';
import 'draughts_record.dart';
import 'draughts_session.dart';
import 'draughts_storage.dart';

class DraughtsAiDuelController extends AiDuelController<DraughtsMove> {
  DraughtsAiDuelController({
    required this.session,
    required this.config,
    DraughtsAi? ai,
    String? recordId,
    DateTime? createdAt,
    super.initiallyPaused,
    super.moveInterval,
  }) : _ai = ai ?? DraughtsAi(),
       createdAt = createdAt ?? DateTime.now().toUtc(),
       recordId =
           recordId ?? 'draughts-duel-${DateTime.now().microsecondsSinceEpoch}';

  DraughtsSession session;
  final AiDuelConfig<DraughtsAiLevel> config;
  final DraughtsAi _ai;
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
  String get resultLabel => session.result?.winner == null
      ? '和棋'
      : '${session.result!.winner!.label}获胜';

  @override
  Future<DraughtsMove?> search() async =>
      (await _ai.search(session, level: config.levelFor(turn)))?.move;

  @override
  void cancelSearch() => _ai.cancel();
  @override
  bool applyMove(DraughtsMove move) => session.applyMove(move);
  @override
  bool undoPosition() => session.undo();

  @override
  void resetPosition() {
    session = DraughtsSession(session.rules);
    createdAt = DateTime.now().toUtc();
    recordId = 'draughts-duel-${createdAt.microsecondsSinceEpoch}';
  }

  @override
  Future<void> savePosition() => DraughtsStorage.save(
    DraughtsRecord.fromSession(
      session,
      id: recordId,
      createdAt: createdAt,
      kind: DraughtsGameKind.aiDuel,
      aiDuel: config,
    ),
  );
}
