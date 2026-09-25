import 'package:flutter/material.dart';
import 'game_session.dart';
import 'game_page.dart';
import 'games/go_game.dart';

export 'board.dart';
export 'game_page.dart';

void main() => runApp(const EasyPlayApp());

class EasyPlayApp extends StatelessWidget {
  const EasyPlayApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EasyPlay',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff1e5eff),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xfff5f7fb),
    ),
    home: const Shell(),
  );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  GameType selected = GameType.go;

  void _openGame(GameType game) {
    if (game != GameType.go) return;
    setState(() => selected = game);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GoGamePage()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: HomePage(onPlay: _openGame, selected: selected),
    ),
  );
}

class HomePage extends StatelessWidget {
  final ValueChanged<GameType> onPlay;
  final GameType selected;
  const HomePage({super.key, required this.onPlay, required this.selected});
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
                        color: const Color(0xff1e5eff),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.blur_on,
                        color: Colors.white,
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
                  ],
                ),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
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
                          onTap: g == GameType.go ? () => onPlay(g) : null,
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
                const ContinueCard(),
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
    final available = type == GameType.go;
    final active = selected && available;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [const Color(0xff1e5eff), const Color(0xff638dff)]
                : available
                ? [Colors.white, const Color(0xfff8faff)]
                : [const Color(0xfff0f1f4), const Color(0xffe9ebef)],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    type.icon,
                    color: active
                        ? Colors.white
                        : available
                        ? const Color(0xff1e5eff)
                        : Colors.black38,
                    size: 28,
                  ),
                  const Spacer(),
                  if (available)
                    Icon(
                      Icons.arrow_outward,
                      color: active ? Colors.white70 : Colors.black26,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '未完成',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.label,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: active ? Colors.white : const Color(0xff16213b),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    type.description,
                    style: TextStyle(
                      color: active ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key});
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
          color: const Color(0xffffe6b3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.blur_on, color: Color(0xff9a6500), size: 31),
      ),
      title: const Text(
        '开始新对局 · 19 路围棋',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: const Text('开始一盘新的围棋对局'),
      trailing: FilledButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GoGamePage()),
        ),
        child: const Text('开始'),
      ),
    ),
  );
}
