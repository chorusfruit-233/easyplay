import 'game_session.dart';
import 'go_ai_settings.dart';
import 'go_sgf.dart';
import 'go_storage.dart';

/// What a stored game looks like on a card or a list row.
class GoRecordSummary {
  const GoRecordSummary({
    required this.title,
    required this.black,
    required this.white,
    required this.footer,
    required this.size,
    required this.moves,
    required this.result,
  });

  final String title;
  final String black;
  final String white;
  final String footer;

  /// Board size in lines, or null when the SGF could not be read.
  final int? size;
  final int? moves;

  /// Human-readable result, or 进行中 while the game has no winner.
  final String result;

  /// Reads the card's contents out of the SGF.
  ///
  /// A game that cannot be parsed still gets a summary — the date comes from the
  /// id — because hiding it would make a saved game look lost.
  static GoRecordSummary of(GoSavedRecord saved) {
    final created = saved.createdAt?.toLocal();
    final title = created == null
        ? '未命名棋谱'
        : '${created.year}-${_two(created.month)}-${_two(created.day)} '
              '${_two(created.hour)}:${_two(created.minute)}';
    final names = _playerNames(saved);
    try {
      final game = GoSgf.importGame(saved.sgf);
      final result = game.winner == null
          ? '进行中'
          : '${game.winner == Side.black ? '黑' : '白'}胜';
      return GoRecordSummary(
        title: title,
        black: names.$1,
        white: names.$2,
        footer: '第 ${game.moves.length} 手 · $result',
        size: game.goConfig.boardSize,
        moves: game.moves.length,
        result: result,
      );
    } catch (_) {
      return GoRecordSummary(
        title: title,
        black: names.$1,
        white: names.$2,
        footer: '无法读取',
        size: null,
        moves: null,
        result: '无法读取',
      );
    }
  }

  /// Who sat on each side.
  ///
  /// The engine is named only when the game says it was the opponent, so a
  /// record played by hand is not mislabelled as human versus computer.
  static (String, String) _playerNames(GoSavedRecord saved) {
    if (!saved.vsComputer ||
        saved.aiSettings?.opponentMode != GoOpponentMode.kataGo) {
      return ('黑方', '白方');
    }
    return saved.humanSide == Side.black ? ('我', '电脑') : ('电脑', '我');
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
