import '../game_page.dart';
import '../game_session.dart';
import '../go_ai_settings.dart';

/// Go game entry point; Go settings and SGF support are implemented in GamePage.
class GoGamePage extends GamePage {
  const GoGamePage({super.key, GoConfig? config, GoAiSettings? aiSettings})
    : super(type: GameType.go, goConfig: config, aiSettings: aiSettings);
}
