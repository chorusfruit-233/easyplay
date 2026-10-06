import 'ui/app_layout.dart';
import 'package:flutter/material.dart';

import 'game_session.dart';
import 'games/go_game.dart';
import 'go_library_page.dart';
import 'go_record_summary.dart';
import 'go_storage.dart';
import 'lan/lan_page.dart';

export 'go_library_page.dart';
export 'go_record_summary.dart';

/// Second-level shell for Go.
///
/// The Go home page and the kifu library live behind one bottom bar so switching
/// between them is not a trip back to the app's home page. The board is opened
/// from here as its own screen: once a game is on it wants the whole display.
class GoSectionPage extends StatefulWidget {
  const GoSectionPage({super.key});

  @override
  State<GoSectionPage> createState() => _GoSectionPageState();
}

class _GoSectionPageState extends State<GoSectionPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => PopScope(
    // Back from the library returns to the Go home page first; only that page
    // leaves the Go section.
    canPop: _tab == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop || _tab == 0) return;
      setState(() => _tab = 0);
    },
    child: Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [GoHomePage(), GoLibraryPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: '棋谱库',
          ),
        ],
      ),
    ),
  );
}

/// Entry screen for Go: start something new, or pick up a stored game.
///
/// The reference product also puts daily problems and an SRS queue here; this
/// keeps the two sections that match what the app actually does.
class GoHomePage extends StatefulWidget {
  const GoHomePage({super.key});

  @override
  State<GoHomePage> createState() => _GoHomePageState();
}

/// How many games the 继续 strip shows before it stops being a glance.
const _recentLimit = 5;

class _GoHomePageState extends State<GoHomePage> {
  List<GoSavedRecord> _recent = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    List<GoSavedRecord> records;
    try {
      records = await GoStorage.recentRecords();
    } catch (_) {
      records = const [];
    }
    if (!mounted) return;
    setState(() {
      _recent = records;
      _loading = false;
    });
  }

  /// Opens the board on top of the shell. The bottom bar belongs to the Go
  /// section, not to a game in progress.
  Future<void> _open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
    // Whatever was just played is now the most recent record.
    if (mounted) await _loadRecent();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('首页'), centerTitle: true),
    body: AppPageList(
      children: [
        _sectionTitle(context, '快速开始'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _startButton(
                icon: Icons.add,
                label: '新建棋谱',
                onPressed: () => _open(const GoRecordPage()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _startButton(
                icon: Icons.smart_toy_outlined,
                label: 'AI 对弈',
                onPressed: () => _open(const GoGamePage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _open(const LanLobbyPage()),
            icon: const Icon(Icons.wifi),
            label: const Text('联机对弈'),
          ),
        ),
        const SizedBox(height: 28),
        _sectionTitle(context, '继续'),
        const SizedBox(height: 4),
        Text(
          '继续您最近的对局',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_recent.isEmpty)
          _emptyRecent(context)
        else
          SizedBox(
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // A shortcut, not the library: the full list lives in 棋谱库.
              itemCount: _recent.length > _recentLimit
                  ? _recentLimit
                  : _recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  _recentCard(context, _recent[index]),
            ),
          ),
      ],
    ),
  );

  Widget _sectionTitle(BuildContext context, String text) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
  );

  Widget _startButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => FilledButton.tonalIcon(
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    label: Text(label),
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
    ),
  );

  Widget _emptyRecent(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 28),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        Icon(
          Icons.history,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        Text(
          '还没有对局',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _recentCard(BuildContext context, GoSavedRecord saved) {
    final colors = Theme.of(context).colorScheme;
    final summary = GoRecordSummary.of(saved);
    return SizedBox(
      width: 156,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _open(GoGamePage(reopen: saved)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.grid_on,
                    size: 22,
                    color: colors.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  summary.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                _playerRow(colors, Side.black, summary.black),
                _playerRow(colors, Side.white, summary.white),
                const Spacer(),
                Text(
                  summary.footer,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerRow(ColorScheme colors, Side side, String name) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: [
        Icon(
          Icons.circle,
          size: 10,
          color: side == Side.black ? const Color(0xff171717) : colors.outline,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
