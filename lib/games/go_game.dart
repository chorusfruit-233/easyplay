import '../game_page.dart';
import '../game_session.dart';

/// Go game entry point; Go settings and SGF support are implemented in GamePage.
class GoGamePage extends GamePage {
  const GoGamePage({super.key, GoConfig? config})
    : super(type: GameType.go, goConfig: config);
}
