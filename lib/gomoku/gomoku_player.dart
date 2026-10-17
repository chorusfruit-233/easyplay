import 'gomoku_ai_level.dart';
import 'gomoku_session.dart';

/// Player decisions use fixed player identities across both opening swaps.
abstract interface class GomokuPlayer {
  String? get failureReason;
  Future<GomokuAction?> decide(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
  });
  void cancel();
  Future<void> dispose();
}
