import 'package:flutter/material.dart';

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
    final name = TextEditingController(text: existing?.name ?? '自定义 KataGo');
    final time = TextEditingController(
      text: (existing?.maxTimeSeconds ?? 3).toString(),
    );
    final threads = TextEditingController(
      text: (existing?.searchThreads ?? 2).toString(),
    );
    final overrides = TextEditingController(
      text: existing?.configOverrides ?? '',
    );
    final key = GlobalKey<FormState>();
    final saved = await showDialog<GoEngineProfile>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '新增 AI 引擎' : '编辑 AI 引擎'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: key,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '配置名称'),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? '请输入名称' : null,
                  ),
                  TextFormField(
                    controller: time,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '每手最大思考时间（秒，0为不限制）',
                    ),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      return parsed == null || parsed < 0 || parsed > 120
                          ? '请输入0至120之间的整数'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: threads,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '搜索线程数（1–16）'),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      return parsed == null || parsed < 1 || parsed > 16
                          ? '请输入1至16之间的整数'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: overrides,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: '高级 KataGo 参数覆盖',
                      hintText:
                          '每行一个参数，例如：\nmaxVisits = 800\nallowResignation = false',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      try {
                        GoEngineLibrary.validateOverrides(value ?? '');
                        return null;
                      } catch (error) {
                        return error.toString().replaceFirst(
                          'Invalid argument(s): ',
                          '',
                        );
                      }
                    },
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        '运行方式由平台选择：Android 使用 KataGo CPU，静态 Web 使用 KataGo WebAssembly。OpenCL 与 TFLite 运行包尚未加入本项目。',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!key.currentState!.validate()) return;
              Navigator.pop(
                context,
                GoEngineProfile(
                  id:
                      existing?.id ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  name: name.text.trim(),
                  maxTimeSeconds: int.parse(time.text),
                  searchThreads: int.parse(threads.text),
                  configOverrides: overrides.text.trim(),
                ),
              );
            },
            child: const Text('保存配置'),
          ),
        ],
      ),
    );
    name.dispose();
    time.dispose();
    threads.dispose();
    overrides.dispose();
    if (saved == null) return;
    try {
      await GoEngineLibrary.save(saved);
      await GoEngineLibrary.setActive(saved.id);
      if (mounted) setState(_reload);
    } catch (error) {
      _message('保存 AI 引擎失败：$error');
    }
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
                    'maxTime=${profile.maxTimeSeconds == 0 ? '无限制' : '${profile.maxTimeSeconds}s'} · ${profile.searchThreads} 线程'
                    '${profile.configOverrides.isEmpty ? '' : ' · 自定义参数'}',
                  ),
                  onTap: () => _activate(profile),
                  trailing: profile.id == GoEngineProfile.builtIn.id
                      ? const Chip(label: Text('内置'))
                      : PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _edit(profile);
                            if (value == 'remove') _remove(profile);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'remove', child: Text('删除')),
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
