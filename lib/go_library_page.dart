import 'package:flutter/material.dart';

import 'game_session.dart';
import 'games/go_game.dart';
import 'go_encoding.dart';
import 'go_record_summary.dart';
import 'go_sgf.dart';
import 'go_storage.dart';

/// Adds an imported kifu to the library.
///
/// Parsing comes first: a corrupt file must be refused rather than stored and
/// then fail every time it is opened. Kept out of the page so the rule can be
/// tested without a platform file picker.
Future<GoSavedRecord> importKifu(String text) async {
  GoSgf.importGame(text);
  return GoStorage.addRecord(text);
}

/// The kifu library: every stored game, and what can be done with one.
///
/// Opening a game hands it to the board screen, which is the editor; this page
/// only manages the files.
class GoLibraryPage extends StatefulWidget {
  const GoLibraryPage({super.key});

  @override
  State<GoLibraryPage> createState() => _GoLibraryPageState();
}

class _GoLibraryPageState extends State<GoLibraryPage> {
  List<GoSavedRecord> _records = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<GoSavedRecord> records;
    try {
      records = await GoStorage.recentRecords();
    } catch (_) {
      records = const [];
    }
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _import() async {
    try {
      final text = await pickKifuText(context);
      if (text == null || !mounted) return;
      await importKifu(text);
      await _load();
      _notice('棋谱已导入');
    } catch (error) {
      _notice('棋谱导入失败：$error');
    }
  }

  /// Removes a game. The confirmation lives here rather than in the row so the
  /// swipe and any future action menu share one path.
  Future<bool> _confirmDelete(GoSavedRecord record) async {
    final summary = GoRecordSummary.of(record);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除棋谱？'),
        content: Text('${summary.title}\n删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    try {
      await GoStorage.deleteRecord(record.id);
      await _load();
      _notice('棋谱已删除');
    } catch (error) {
      _notice('删除失败：$error');
    }
    return false;
  }

  Future<void> _open(GoSavedRecord record) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => GoGamePage(reopen: record)),
    );
    // Whatever was played is saved under the same id, so the row's move count
    // and result may have moved on.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('棋谱库'),
      actions: [
        IconButton(
          tooltip: '导入 SGF',
          onPressed: _import,
          icon: const Icon(Icons.file_open_outlined),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _records.isEmpty
        ? _empty(context)
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _records.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) => _row(context, _records[index]),
            ),
          ),
  );

  Widget _empty(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.collections_bookmark_outlined,
              size: 56,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('还没有棋谱', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '下过的对局会自动保存到这里，也可以导入 SGF 文件。',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: _import,
              icon: const Icon(Icons.file_open_outlined, size: 20),
              label: const Text('导入 SGF'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, GoSavedRecord record) {
    final colors = Theme.of(context).colorScheme;
    final summary = GoRecordSummary.of(record);
    return Dismissible(
      key: ValueKey(record.id.isEmpty ? record.sgf : record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: colors.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
      ),
      confirmDismiss: (_) => _confirmDelete(record),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.grid_on,
            color: colors.onTertiaryContainer,
            size: 22,
          ),
        ),
        title: Text(
          summary.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                _stone(colors, Side.black),
                const SizedBox(width: 5),
                Text(summary.black),
                const SizedBox(width: 12),
                _stone(colors, Side.white),
                const SizedBox(width: 5),
                Text(summary.white),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (summary.size != null) '${summary.size} 路',
                summary.footer,
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
        onTap: () => _open(record),
      ),
    );
  }

  Widget _stone(ColorScheme colors, Side side) => Icon(
    Icons.circle,
    size: 10,
    color: side == Side.black ? const Color(0xff171717) : colors.outline,
  );
}
