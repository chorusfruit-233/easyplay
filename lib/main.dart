import 'doudizhu/widgets/doudizhu_home_page.dart';
import 'xiangqi/widgets/xiangqi_home_page.dart';
import 'package:flutter/material.dart';
import 'game_session.dart';
import 'go_section_page.dart';
import 'app_theme.dart';
import 'theme_controller.dart';
import 'theme_settings_page.dart';
import 'settings_page.dart';
import 'draughts/widgets/draughts_new_game_page.dart';
import 'chess/widgets/chess_home_page.dart';
import 'gomoku/widgets/gomoku_home_page.dart';
import 'gomoku/widgets/gomoku_lan_pages.dart';
import 'home_page.dart';

export 'board.dart';
export 'home_page.dart';
export 'game_page.dart';

void main() => runApp(const EasyPlayApp());

class EasyPlayApp extends StatefulWidget {
  const EasyPlayApp({super.key, this.themeController});
  final ThemeController? themeController;
  @override
  State<EasyPlayApp> createState() => _EasyPlayAppState();
}

class _EasyPlayAppState extends State<EasyPlayApp> with WidgetsBindingObserver {
  late final _theme = widget.themeController ?? ThemeController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _theme.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _theme.updateSystemColors();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _theme,
    builder: (context, _) => MaterialApp(
      title: 'EasyPlay',
      debugShowCheckedModeBanner: false,
      themeMode: _theme.mode,
      theme: AppTheme.fromScheme(
        _theme.scheme(dark: false, color: _theme.keyColor),
      ),
      darkTheme: AppTheme.fromScheme(
        _theme.scheme(dark: true, color: _theme.keyColor),
      ),
      builder: (context, child) => AnnotatedRegion(
        value: AppTheme.systemBars(Theme.of(context).colorScheme),
        child: AppPageScale(scale: _theme.pageScale, child: child!),
      ),
      home: Shell(theme: _theme),
    ),
  );
}

class Shell extends StatefulWidget {
  final ThemeController theme;
  const Shell({super.key, required this.theme});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  // Every entry into Go goes through the section shell, so the board and the
  // library always share the same bottom bar.
  void _openGame(GameType game) {
    if (game == GameType.doudizhu) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const DouDizhuHomePage()),
      );
      return;
    }
    if (game == GameType.xiangqi) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const XiangqiHomePage()),
      );
      return;
    }
    if (game == GameType.gomoku) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => GomokuHomePage(
            lanBuilder: (_, variant) => GomokuLanLobbyPage(variant: variant),
          ),
        ),
      );
      return;
    }
    if (game == GameType.chess) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const ChessHomePage()),
      );
      return;
    }
    if (game == GameType.checkers) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const DraughtsNewGamePage()),
      );
      return;
    }
    if (game != GameType.go) return;
    _openGoSection();
  }

  void _openGoSection() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const GoSectionPage()),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: HomePage(
        onPlay: _openGame,
        onSettings: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SettingsPage(theme: widget.theme)),
        ),
      ),
    ),
  );
}
