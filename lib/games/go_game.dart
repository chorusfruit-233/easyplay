import '../game_page.dart';
import '../game_session.dart';
import '../go_ai_settings.dart';

/// Go game entry point; Go settings and SGF support are implemented in GamePage.
class GoGamePage extends GamePage {
  const GoGamePage({
    super.key,
    GoConfig? config,
    super.aiSettings,
    super.askForSetup,
    super.reopen,
  }) : super(type: GameType.go, goConfig: config);
}

/// A blank board with no engine: the "新建棋谱" entry, for playing a game out by
/// hand or setting up a position to record.
class GoRecordPage extends GamePage {
  const GoRecordPage({super.key, GoConfig? config})
    : super(
        type: GameType.go,
        goConfig: config,
        askForSetup: false,
        aiSettings: const GoAiSettings(opponentMode: GoOpponentMode.local),
      );
}
