import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'go_model_catalog.dart';
import 'go_models.dart';
import 'katago.dart';

class GoModelManagerPage extends StatefulWidget {
  const GoModelManagerPage({super.key});

  @override
  State<GoModelManagerPage> createState() => _GoModelManagerPageState();
}

class _GoModelManagerPageState extends State<GoModelManagerPage> {
  late Future<_ModelSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _snapshot = _loadSnapshot();
  }

  Future<_ModelSnapshot> _loadSnapshot() async => _ModelSnapshot(
    models: await GoModelLibrary.available(),
    activeId: await GoModelLibrary.activeId(),
  );

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _activate(String id) async {
    try {
      await GoModelLibrary.setActive(id);
      if (mounted) setState(_reload);
    } catch (error) {
      _message('无法选择模型：$error');
    }
  }

  Future<void> _importFile() async {
    try {
      var kind = GoModelKind.standard;
      if (!mounted) return;
      final selectedKind = await showDialog<GoModelKind>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('模型类型'),
          children: [
            for (final value in GoModelKind.values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, value),
                child: Text(value.label),
              ),
          ],
        ),
      );
      if (selectedKind == null) return;
      kind = selectedKind;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: kind == GoModelKind.tflite
            ? ['tflite', 'lite']
            : ['gz'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw StateError('无法读取所选模型文件');
      final filename = file.name;
      final label = filename.replaceFirst(
        RegExp(r'\.gz$', caseSensitive: false),
        '',
      );
      final info = await GoModelLibrary.install(
        name: label,
        fileName: filename,
        bytes: bytes,
        kind: kind,
      );
      if (info.kind == GoModelKind.standard) {
        await GoModelLibrary.setActive(info.id);
      }
      if (!mounted) return;
      setState(_reload);
      _message('模型已导入：${info.name}（${info.kind.label}）');
    } catch (error) {
      _message('导入模型失败：$error');
    }
  }

  /// Download Models: a short list of known networks, mirroring the reference
  /// product. Runtime entries ("latest" / "strongest") are resolved against
  /// katagotraining.org and fall back to a pinned snapshot when offline.
  Future<void> _download() async {
    final installed = (await _snapshot).models;
    if (!mounted) return;
    final picked = await showModalBottomSheet<GoModelCatalogEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _CatalogSheet(installed: installed),
    );
    if (picked == null || !mounted) return;
    await _runDownload(picked);
  }

  Future<void> _runDownload(GoModelCatalogEntry entry) async {
    final installed = (await _snapshot).models;
    GoModelDownload? target;
    var usedFallback = false;
    try {
      target = entry.isRemote
          ? await GoModelCatalog.resolve(entry)
          : GoModelDownload(
              name: GoModelCatalog.downloadNameFor(entry),
              url: entry.url!,
              bytes: entry.bytes,
              sha256: entry.sha256,
            );
    } catch (_) {
      target = GoModelCatalog.fallbackFor(entry);
      usedFallback = true;
    }
    if (target == null) {
      _message('无法解析 ${entry.displayName} 的下载地址');
      return;
    }
    if (installed.any((m) => m.name == target!.name)) {
      _message('${entry.displayName} 已下载');
      return;
    }
    if (!mounted) return;

    // Progress state lives in the sheet so the row can show a bar.
    final downloaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => _DownloadProgress(
        entry: entry,
        target: target!,
        usedFallback: usedFallback,
      ),
    );
    if (downloaded == true && mounted) {
      setState(_reload);
      _message('${entry.displayName} 已安装');
    }
  }

  Future<void> _remove(GoModelInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型？'),
        content: Text('将从本机存储中删除“${info.name}”。'),
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
    if (confirmed != true) return;
    try {
      await GoModelLibrary.remove(info.id);
      if (!mounted) return;
      setState(_reload);
      _message('模型已删除');
    } catch (error) {
      _message('删除模型失败：$error');
    }
  }

  String _size(int bytes) {
    if (bytes == 0) return '随应用内置';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('KataGo 引擎与模型'),
      actions: kIsWeb
          ? const []
          : [
              PopupMenuButton<String>(
                tooltip: '添加模型',
                onSelected: (value) {
                  if (value == 'import') _importFile();
                  if (value == 'download') _download();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'import', child: Text('导入模型文件')),
                  PopupMenuItem(value: 'download', child: Text('从 URL 下载')),
                ],
              ),
            ],
    ),
    body: FutureBuilder<_ModelSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('读取模型列表失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return RadioGroup<String>(
          groupValue: data.activeId,
          onChanged: (id) {
            if (id != null) _activate(id);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                kIsWeb
                    ? 'Web 静态部署只使用随应用发布的 KataGo b6 模型。'
                    : '选择默认模型。导入或下载的模型只保存在本机设备中，不需要服务端。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final model in data.models)
                Card(
                  child: ListTile(
                    leading: Radio<String>(value: model.id),
                    title: Text(model.name),
                    subtitle: Text(
                      '${model.kind.label} · ${model.fileName} · ${_size(model.bytes)}\nSHA-256 ${model.sha256}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: model.bundled
                        ? const Chip(label: Text('内置'))
                        : IconButton(
                            tooltip: '删除模型',
                            onPressed: () => _remove(model),
                            icon: const Icon(Icons.delete_outline),
                          ),
                    onTap: () => _activate(model.id),
                  ),
                ),
              if (!kIsWeb) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _importFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('导入标准、人类棋风或 TFLite 模型'),
                ),
                OutlinedButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('从 URL 下载模型'),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _ModelSnapshot {
  final List<GoModelInfo> models;
  final String activeId;
  const _ModelSnapshot({required this.models, required this.activeId});
}

/// The Download Models list: name, size, and current state per row.
class _CatalogSheet extends StatelessWidget {
  final List<GoModelInfo> installed;
  const _CatalogSheet({required this.installed});

  String _sizeLabel(int? bytes) {
    if (bytes == null) return '大小未知';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = GoModelCatalog.entries();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('下载模型', style: Theme.of(context).textTheme.titleLarge),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                '内置 b6 适合基础对弈。更强的模型需要下载，'
                '人类棋风模型需要 OpenCL 运行方式。',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
            for (final entry in entries)
              _CatalogRow(
                entry: entry,
                installed: installed,
                sizeLabel: _sizeLabel(
                  entry.bytes ?? GoModelCatalog.fallbackFor(entry)?.bytes,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  final GoModelCatalogEntry entry;
  final List<GoModelInfo> installed;
  final String sizeLabel;
  const _CatalogRow({
    required this.entry,
    required this.installed,
    required this.sizeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolved = GoModelCatalog.fallbackFor(entry);
    final already = installed.any(
      (m) => m.name == (resolved?.name ?? entry.id),
    );
    // Entries with neither a pinned URL nor an endpoint are retired upstream.
    final retired = entry.url == null && entry.endpoint == null;
    final enabled = !already && !retired;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: enabled ? () => Navigator.pop(context, entry) : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: enabled ? null : colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.description} · $sizeLabel',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (already)
                Text(
                  '已下载',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                )
              else if (retired)
                Text(
                  '不可用',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                )
              else
                const Icon(Icons.download_outlined, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Download + verify, with the states the reference product exposes:
/// downloading, verifying, checksum mismatch, network error, cancelled.
class _DownloadProgress extends StatefulWidget {
  final GoModelCatalogEntry entry;
  final GoModelDownload target;
  final bool usedFallback;
  const _DownloadProgress({
    required this.entry,
    required this.target,
    required this.usedFallback,
  });

  @override
  State<_DownloadProgress> createState() => _DownloadProgressState();
}

class _DownloadProgressState extends State<_DownloadProgress> {
  final _client = KataGoDownloadClient();
  double _progress = 0;
  bool _verifying = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _client.client.close();
    super.dispose();
  }

  Future<void> _start() async {
    final target = widget.target;
    try {
      final spec = KataGoModelSpec(
        id: widget.entry.id,
        displayName: widget.entry.displayName,
        url: target.url,
        sha256: target.sha256,
      );
      final bytes = await _client.download(
        spec,
        onProgress: (received, total) {
          if (!mounted || total == null || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      setState(() => _verifying = true);
      final info = await GoModelLibrary.install(
        name: target.name,
        fileName: target.url.pathSegments.isEmpty
            ? 'katago-model.bin.gz'
            : target.url.pathSegments.last,
        bytes: bytes,
        expectedSha256: target.sha256,
        kind: GoModelCatalog.kindOf(widget.entry),
      );
      if (info.kind == GoModelKind.standard) {
        await GoModelLibrary.setActive(info.id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _failure = _describe(error);
      });
    }
  }

  /// Names the failure the way the reference does, so a checksum problem is
  /// distinguishable from a transport problem.
  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('校验') || text.contains('checksum')) {
      return '校验和不匹配：下载内容与预期不符，已丢弃';
    }
    if (text.contains('HTTP')) return '网络错误，请稍后重试：$text';
    return '下载失败：$text';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.entry.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              widget.target.name,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            if (widget.usedFallback)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '无法查询最新网络，改用内置快照（旧版）',
                  style: TextStyle(fontSize: 12, color: colors.error),
                ),
              ),
            const SizedBox(height: 16),
            if (_failure == null) ...[
              LinearProgressIndicator(
                value: _verifying || _progress == 0 ? null : _progress,
              ),
              const SizedBox(height: 8),
              Text(
                _verifying ? '校验中…' : '下载中 ${(_progress * 100).round()}%',
                style: const TextStyle(fontSize: 13),
              ),
            ] else ...[
              Text(_failure!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      _client.client.close();
                      Navigator.pop(context, false);
                    },
                    child: Text(_failure == null ? '取消' : '关闭'),
                  ),
                ),
                if (_failure != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _failure = null;
                          _progress = 0;
                        });
                        _start();
                      },
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
