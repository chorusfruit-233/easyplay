import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  Future<void> _download() async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final url = TextEditingController();
    final checksum = TextEditingController();
    var kind = GoModelKind.standard;
    KataGoDownloadClient? activeClient;
    var downloading = false;
    var progress = 0.0;
    String? failure;
    var installed = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          canPop: !downloading,
          child: AlertDialog(
            title: const Text('下载 KataGo 模型'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    DropdownButtonFormField<GoModelKind>(
                      key: ValueKey(kind),
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: '模型类型'),
                      items: GoModelKind.values
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.label),
                            ),
                          )
                          .toList(),
                      onChanged: downloading
                          ? null
                          : (v) => setDialogState(() => kind = v ?? kind),
                    ),
                    TextButton(
                      onPressed: downloading
                          ? null
                          : () => setDialogState(() {
                              kind = GoModelKind.human;
                              name.text = 'KataGo b18 人类棋风';
                              url.text =
                                  'https://github.com/lightvector/KataGo/releases/download/v1.15.0/b18c384nbt-humanv0.bin.gz';
                            }),
                      child: const Text('填写官方人类棋风模型地址'),
                    ),
                    TextFormField(
                      controller: name,
                      enabled: !downloading,
                      decoration: const InputDecoration(labelText: '模型名称'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? '请输入模型名称'
                          : null,
                    ),
                    TextFormField(
                      controller: url,
                      enabled: !downloading,
                      decoration: const InputDecoration(labelText: '模型下载 URL'),
                      validator: (value) {
                        final parsed = Uri.tryParse(value ?? '');
                        return parsed == null ||
                                !parsed.hasScheme ||
                                !['http', 'https'].contains(parsed.scheme)
                            ? '请输入有效的 HTTP(S) 地址'
                            : null;
                      },
                    ),
                    TextFormField(
                      controller: checksum,
                      enabled: !downloading,
                      decoration: const InputDecoration(
                        labelText: 'SHA-256（可选）',
                      ),
                    ),
                    if (downloading) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: progress == 0 ? null : progress,
                      ),
                      const SizedBox(height: 8),
                      Text('${(progress * 100).round()}%'),
                    ],
                    if (failure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          failure!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  activeClient?.client.close();
                  Navigator.pop(dialogContext);
                },
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: downloading
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() {
                          downloading = true;
                          failure = null;
                        });
                        final uri = Uri.parse(url.text.trim());
                        final spec = KataGoModelSpec(
                          id: 'downloaded',
                          displayName: name.text.trim(),
                          url: uri,
                          sha256: checksum.text.trim().isEmpty
                              ? null
                              : checksum.text.trim(),
                        );
                        final client = KataGoDownloadClient();
                        activeClient = client;
                        try {
                          final bytes = await client.download(
                            spec,
                            onProgress: (received, total) {
                              if (dialogContext.mounted &&
                                  total != null &&
                                  total > 0) {
                                setDialogState(
                                  () => progress = received / total,
                                );
                              }
                            },
                          );
                          final info = await GoModelLibrary.install(
                            name: name.text.trim(),
                            fileName: uri.pathSegments.isEmpty
                                ? 'katago-model.bin.gz'
                                : uri.pathSegments.last,
                            bytes: bytes,
                            expectedSha256: spec.sha256,
                            kind: kind,
                          );
                          if (info.kind == GoModelKind.standard) {
                            await GoModelLibrary.setActive(info.id);
                          }
                          installed = true;
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              downloading = false;
                              failure = '下载或校验失败：$error';
                            });
                          }
                        } finally {
                          client.client.close();
                        }
                      },
                child: const Text('下载并安装'),
              ),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    url.dispose();
    checksum.dispose();
    if (installed && mounted) {
      setState(_reload);
      _message('KataGo 模型已安装');
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
