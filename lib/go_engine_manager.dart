import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'go_file_service.dart';
import 'go_engine_editor.dart';
import 'go_engine_runtime.dart';

import 'go_engine_profiles.dart';

class GoEngineManagerPage extends StatefulWidget {
  const GoEngineManagerPage({super.key});

  @override
  State<GoEngineManagerPage> createState() => _GoEngineManagerPageState();
}

class _GoEngineManagerPageState extends State<GoEngineManagerPage> {
  late Future<_EngineSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _snapshot = _load();
  }

  Future<_EngineSnapshot> _load() async => _EngineSnapshot(
    profiles: await GoEngineLibrary.available(),
    activeId: await GoEngineLibrary.activeId(),
  );

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit([GoEngineProfile? existing]) async {
    final saved = await Navigator.push<GoEngineProfile>(
      context,
      MaterialPageRoute(builder: (_) => GoEngineEditor(profile: existing)),
    );
    if (saved == null || !mounted) return;
    await GoEngineLibrary.setActive(saved.id);
    if (mounted) setState(_reload);
  }

  Future<void> _export(GoEngineProfile profile) async {
    try {
      await GoFileService.saveSgf(
        const JsonEncoder.withIndent('  ').convert(profile.toJson()),
        fileName: 'katago-engine-${profile.id}.json',
      );
    } catch (error) {
      _message('导出失败：$error');
    }
  }

  Future<void> _import() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null) return;
      final json = (jsonDecode(utf8.decode(picked.files.single.bytes!)) as Map)
          .cast<String, Object?>();
      json['id'] = DateTime.now().microsecondsSinceEpoch.toString();
      final profile = GoEngineProfile.fromJson(json);
      await GoEngineLibrary.save(profile);
      if (mounted) setState(_reload);
    } catch (error) {
      _message('导入失败：$error');
    }
  }

  Future<void> _runtime(GoEngineProfile profile) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoEngineRuntimePage(profile: profile)),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _activate(GoEngineProfile profile) async {
    try {
      await GoEngineLibrary.setActive(profile.id);
      if (mounted) setState(_reload);
    } catch (error) {
      _message('无法设为默认引擎：$error');
    }
  }

  Future<void> _remove(GoEngineProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 AI 引擎配置？'),
        content: Text('将删除“${profile.name}”配置。'),
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
      await GoEngineLibrary.remove(profile.id);
      if (mounted) setState(_reload);
    } catch (error) {
      _message('删除配置失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AI 引擎'),
      actions: [
        IconButton(
          tooltip: '导入引擎配置',
          onPressed: _import,
          icon: const Icon(Icons.file_open_outlined),
        ),
        IconButton(
          tooltip: '新增引擎配置',
          onPressed: _edit,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: FutureBuilder<_EngineSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('读取引擎配置失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('AI 引擎配置可调整搜索时间、线程和 KataGo 参数。主网络模型在新局设置中选择。'),
            const SizedBox(height: 12),
            for (final profile in data.profiles)
              Card(
                child: ListTile(
                  leading: Radio<String>(
                    value: profile.id,
                    groupValue: data.activeId,
                    onChanged: (_) => _activate(profile),
                  ),
                  title: Text(profile.name),
                  subtitle: Text(
                    '${profile.backend.label} · maxTime=${profile.maxTimeSeconds == 0 ? '无限制' : '${profile.maxTimeSeconds}s'} · ${profile.searchThreads} 线程'
                    '${profile.configOverrides.isEmpty ? '' : ' · 自定义参数'}',
                  ),
                  onTap: () => _activate(profile),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') await _edit(profile);
                      if (value == 'runtime') await _runtime(profile);
                      if (value == 'export') await _export(profile);
                      if (value == 'remove') await _remove(profile);
                      if (value == 'reset') {
                        await GoEngineLibrary.resetBuiltIn();
                        if (mounted) setState(_reload);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(
                        value: 'runtime',
                        child: Text('运行检测与 OpenCL 调优'),
                      ),
                      const PopupMenuItem(value: 'export', child: Text('导出配置')),
                      if (profile.id == GoEngineProfile.builtIn.id)
                        const PopupMenuItem(
                          value: 'reset',
                          child: Text('恢复内置配置'),
                        )
                      else
                        const PopupMenuItem(value: 'remove', child: Text('删除')),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _EngineSnapshot {
  final List<GoEngineProfile> profiles;
  final String activeId;
  const _EngineSnapshot({required this.profiles, required this.activeId});
}
