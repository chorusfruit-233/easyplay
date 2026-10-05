import 'doudizhu/widgets/doudizhu_home_page.dart';
import 'xiangqi/widgets/xiangqi_home_page.dart';
import 'package:flutter/material.dart';
import 'game_session.dart';
import 'game_page.dart';
import 'go_section_page.dart';
import 'app_theme.dart';
import 'theme_controller.dart';
import 'theme_settings_page.dart';
import 'settings_page.dart';
import 'draughts/widgets/draughts_new_game_page.dart';
import 'chess/widgets/chess_home_page.dart';
import 'gomoku/widgets/gomoku_home_page.dart';
import 'gomoku/widgets/gomoku_lan_pages.dart';
import 'lan/lan_quick_join.dart';

export 'board.dart';
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
  GameType selected = GameType.go;

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
    setState(() => selected = game);
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
        selected: selected,
        onSettings: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SettingsPage(theme: widget.theme)),
        ),
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  final ValueChanged<GameType> onPlay;
  final GameType selected;
  final VoidCallback onSettings;
  const HomePage({
    super.key,
    required this.onPlay,
    required this.selected,
    required this.onSettings,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth > 760;
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.blur_on,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'EASYPLAY',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        fontSize: 19,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onSettings,
                      tooltip: '设置',
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
                const LanQuickJoinCard(),
                const SizedBox(height: 34),
                Text(
                  '今天，\n来一局好棋。',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '从围棋开始，专注每一步棋。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                GridView.count(
                  crossAxisCount: wide ? 3 : 1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: wide ? 1.5 : 2.25,
                  children: GameType.values
                      .map(
                        (g) => GameCard(
                          type: g,
                          selected: selected == g,
                          onTap: () => onPlay(g),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '新对局',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ContinueCard(onStart: () => onPlay(GameType.go)),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class GameCard extends StatelessWidget {
  final GameType type;
  final bool selected;
  final VoidCallback? onTap;
  const GameCard({
    super.key,
    required this.type,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final available = onTap != null;
    final active = selected && available;
    final colors = Theme.of(context).colorScheme;
    // Deliberately not an InkWell/Ink pair.
    //
    // With the ink pair in place the card did not react to the Material 3
    // stretch overscroll effect while the surrounding text did. Removing it
    // fixes that, confirmed on device: debugPaintLayerBordersEnabled showed the
    // card owning a compositing layer that the text did not have, and the card
    // began stretching once the pair was replaced. Verified by elimination that
    // neither borderRadius nor boxShadow is responsible, so both stay below.
    //
    // The mechanism is not fully established. The working theory is that the
    // ink features create a separate layer the shader-based stretch
    // ImageFilter does not reach; what is established is that this widget
    // structure behaves correctly on device.
    //
    // Trade-off: no ripple on tap. Add a pressed-state animation here rather
    // than going back to InkWell if that feedback is wanted.
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [colors.primaryContainer, colors.primaryContainer]
                : available
                ? [colors.surface, colors.surfaceContainerLowest]
                : [colors.surfaceContainerHigh, colors.surfaceContainer],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                type.icon,
                color: active
                    ? colors.onPrimaryContainer
                    : available
                    ? colors.primary
                    : colors.onSurfaceVariant,
                size: 30,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: active
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (available)
                Icon(
                  Icons.arrow_outward,
                  color: active
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '未完成',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.onStart});
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: ListTile(
      contentPadding: const EdgeInsets.all(14),
      leading: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.blur_on,
          color: Theme.of(context).colorScheme.onTertiaryContainer,
          size: 31,
        ),
      ),
      title: const Text(
        '开始新对局 · 19 路围棋',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: const Text('开始一盘新的围棋对局'),
      trailing: FilledButton(onPressed: onStart, child: const Text('开始')),
    ),
  );
}
