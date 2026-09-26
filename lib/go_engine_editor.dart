import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'go_ai_settings.dart';
import 'go_engine_profiles.dart';
import 'go_human_profiles.dart';
import 'go_models.dart';

class GoEngineEditor extends StatefulWidget {
  final GoEngineProfile? profile;
  const GoEngineEditor({super.key, this.profile});
  @override
  State<GoEngineEditor> createState() => _GoEngineEditorState();
}

class _GoEngineEditorState extends State<GoEngineEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.profile?.name ?? '自定义 KataGo',
  );
  late final _time = TextEditingController(
    text: '${widget.profile?.maxTimeSeconds ?? 3}',
  );
  late final _threads = TextEditingController(
    text: '${widget.profile?.searchThreads ?? 2}',
  );
  late final _gpu = TextEditingController(
    text: '${widget.profile?.openclGpuIdx ?? 0}',
  );
  late final _library = TextEditingController(
    text: widget.profile?.openclLibraryName ?? 'libOpenCL.so',
  );
  late final _cfg = TextEditingController(
    text: widget.profile?.customConfig ?? '',
  );
  late final _overrides = TextEditingController(
    text: widget.profile?.configOverrides ?? '',
  );
  late GoEngineBackend _backend =
      widget.profile?.backend ?? GoEngineBackend.cpu;
  late List<GoEngineOverrideRule> _normal = [...?widget.profile?.overrideRules];
  late List<GoEngineOverrideRule> _human = [
    ...?widget.profile?.humanOverrideRules,
  ];
  late String? _modelId = widget.profile?.modelId;
  late String? _humanId = widget.profile?.humanModelId;
  List<GoModelInfo> _models = [GoModelLibrary.bundledModel];
  String? _error;

  @override
  void initState() {
    super.initState();
    GoModelLibrary.available().then((models) {
      if (mounted) setState(() => _models = models);
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _time,
      _threads,
      _gpu,
      _library,
      _cfg,
      _overrides,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      child,
      const SizedBox(height: 20),
    ],
  );

  String? _configValidator(String? value) {
    try {
      GoEngineLibrary.validateOverrides(value ?? '');
      return null;
    } catch (error) {
      return '$error';
    }
  }

  Future<void> _importConfig() async {
    try {
      final files = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['cfg', 'txt'],
        withData: true,
      );
      if (files == null) return;
      final source = utf8.decode(files.files.single.bytes!);
      GoEngineLibrary.validateOverrides(source);
      if (mounted) setState(() => _cfg.text = source);
    } catch (error) {
      if (mounted) setState(() => _error = '导入配置失败：$error');
    }
  }

  Future<void> _defaults(bool human) async {
    final catalog = await GoHumanOverrideCatalog.load();
    final defaults = <GoEngineOverrideRule>[];
    for (final rule in human ? catalog.humanRules : catalog.normalRules) {
      defaults.add(
        GoEngineOverrideRule(
          id: rule.id,
          displayName: rule.displayName,
          rankMin: rule.rankMin,
          rankMax: rule.rankMax,
          configText: await catalog.loadConfig(rule),
        ),
      );
    }
    if (mounted) {
      setState(() {
        if (human) {
          _human = defaults;
        } else {
          _normal = defaults;
        }
      });
    }
  }

  Future<void> _editRule(bool human, [int? index]) async {
    final rules = human ? _human : _normal;
    final old = index == null ? null : rules[index];
    final rule = await showDialog<GoEngineOverrideRule>(
      context: context,
      builder: (_) => _OverrideDialog(rule: old),
    );
    if (rule == null || !mounted) return;
    final updated = [...rules];
    if (index == null) {
      updated.add(rule);
    } else {
      updated[index] = rule;
    }
    try {
      GoEngineOverrideRule.validateList(updated);
      setState(() {
        if (human) {
          _human = updated;
        } else {
          _normal = updated;
        }
        _error = null;
      });
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  Widget _rules(bool human) {
    final rules = human ? _human : _normal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          human ? '人类棋风 override 规则' : '普通棋风 override 规则',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(human ? '自动应用内置段位配置，再合并此处的全局和段位规则。' : '先应用全局规则，再应用命中的段位规则。'),
        for (var i = 0; i < rules.length; i++)
          Card(
            child: ListTile(
              title: Text(rules[i].displayName),
              subtitle: Text(
                rules[i].isGlobal
                    ? '所有段位'
                    : '${GoAiSettings.humanRankLabel(rules[i].rankMin!)} 至 ${GoAiSettings.humanRankLabel(rules[i].rankMax!)}',
              ),
              onTap: () => _editRule(human, i),
              trailing: IconButton(
                tooltip: '删除规则',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => rules.removeAt(i)),
              ),
            ),
          ),
        Wrap(
          spacing: 12,
          children: [
            TextButton.icon(
              onPressed: () => _editRule(human),
              icon: const Icon(Icons.add),
              label: const Text('添加规则'),
            ),
            TextButton(
              onPressed: () => _defaults(human),
              child: const Text('恢复内置规则'),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    try {
      final base =
          widget.profile?.toJson() ??
          <String, Object>{
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
          };
      final profile = GoEngineProfile.fromJson({
        ...base,
        'name': _name.text.trim(),
        'backend': _backend.name,
        'maxTimeSeconds': int.parse(_time.text),
        'searchThreads': int.parse(_threads.text),
        'openclGpuIdx': int.tryParse(_gpu.text),
        'openclLibraryName': _library.text.trim(),
        'customConfig': _cfg.text,
        'configOverrides': _overrides.text,
        'modelId': _modelId,
        'humanModelId': _humanId,
        'overrideRules': _normal.map((r) => r.toJson()).toList(),
        'humanOverrideRules': _human.map((r) => r.toJson()).toList(),
      });
      final main = _models.where((m) => m.id == _modelId).firstOrNull;
      final human = _models.where((m) => m.id == _humanId).firstOrNull;
      if (main != null) {
        GoModelCompatibility.validate(
          model: main,
          engine: profile,
          humanModel: human,
        );
      }
      if (_backend == GoEngineBackend.tflite && human != null) {
        throw ArgumentError('TFLite 不支持 human model');
      }
      await GoEngineLibrary.save(profile);
      if (mounted) Navigator.pop(context, profile);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.profile == null ? '新增 AI 引擎' : '编辑 AI 引擎'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _field(
                '配置名称',
                TextFormField(
                  controller: _name,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入名称' : null,
                ),
              ),
              _field(
                '运行方式',
                DropdownButtonFormField<GoEngineBackend>(
                  isExpanded: true,
                  initialValue: _backend,
                  items: GoEngineBackend.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == GoEngineBackend.tflite
                                ? '${v.label}（当前不可用）'
                                : v.label,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _backend = v ?? _backend),
                ),
              ),
              if (kIsWeb)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(
                    '静态 Web 使用 WASM CPU；OpenCL 配置在浏览器中以 CPU 运行，TFLite 模型不能在浏览器使用。',
                  ),
                ),
              _field(
                '主模型',
                DropdownButtonFormField<String>(
                  key: ValueKey('main-$_modelId-${_models.length}'),
                  initialValue: _models.any((m) => m.id == _modelId)
                      ? _modelId
                      : '',
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('在新局设置中选择')),
                    ..._models.map(
                      (m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          '${m.name} · ${m.kind.label}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _modelId = v == '' ? null : v),
                ),
              ),
              _field(
                '独立人类棋风模型',
                DropdownButtonFormField<String>(
                  key: ValueKey('human-$_humanId-${_models.length}'),
                  initialValue:
                      _models.any((m) => m.id == _humanId && m.isHumanModel)
                      ? _humanId
                      : '',
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('不使用')),
                    ..._models
                        .where((m) => m.isHumanModel)
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              m.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                  ],
                  onChanged: (v) =>
                      setState(() => _humanId = v == '' ? null : v),
                ),
              ),
              if (_backend == GoEngineBackend.opencl) ...[
                _field(
                  'OpenCL GPU 编号',
                  TextFormField(
                    controller: _gpu,
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        (int.tryParse(v ?? '') ?? -1) < 0 ? '请输入非负整数' : null,
                  ),
                ),
                _field(
                  '设备 OpenCL 驱动库',
                  TextFormField(
                    controller: _library,
                    decoration: const InputDecoration(
                      hintText: 'libOpenCL.so 或 /vendor/lib64/libOpenCL.so',
                    ),
                  ),
                ),
              ],
              _field(
                '每手思考时间（秒，0 为不限）',
                TextFormField(
                  controller: _time,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 0 || n > 120 ? '请输入 0 至 120' : null;
                  },
                ),
              ),
              _field(
                '搜索线程（1–16）',
                TextFormField(
                  controller: _threads,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 16 ? '请输入 1 至 16' : null;
                  },
                ),
              ),
              Text('自定义配置', style: Theme.of(context).textTheme.titleMedium),
              const Text(
                '合并顺序：内置参数 → 自定义 cfg → 全局/段位规则 → 最终参数覆盖。棋盘、规则和人类段位以新局设置为准。',
              ),
              TextButton.icon(
                onPressed: _importConfig,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('导入 .cfg 文件'),
              ),
              _field(
                '自定义 cfg',
                TextFormField(
                  controller: _cfg,
                  minLines: 4,
                  maxLines: 12,
                  validator: _configValidator,
                ),
              ),
              _rules(false),
              _rules(true),
              _field(
                '最终 KataGo 参数覆盖',
                TextFormField(
                  controller: _overrides,
                  minLines: 3,
                  maxLines: 8,
                  validator: _configValidator,
                  decoration: const InputDecoration(
                    hintText: 'maxVisits = 800\nallowResignation = false',
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(onPressed: _save, child: const Text('保存配置')),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OverrideDialog extends StatefulWidget {
  final GoEngineOverrideRule? rule;
  const _OverrideDialog({this.rule});
  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  late final _name = TextEditingController(
    text: widget.rule?.displayName ?? '自定义规则',
  );
  late final _text = TextEditingController(text: widget.rule?.configText ?? '');
  late bool _global = widget.rule?.isGlobal ?? true;
  late int _min = widget.rule?.rankMin ?? 20;
  late int _max = widget.rule?.rankMax ?? -8;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  Widget _rank(String label, int selected, ValueChanged<int> changed) =>
      DropdownButtonFormField<int>(
        initialValue: selected,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var i = 20; i >= -8; i--)
            DropdownMenuItem(
              value: i,
              child: Text(GoAiSettings.humanRankLabel(i)),
            ),
        ],
        onChanged: (v) {
          if (v != null) changed(v);
        },
      );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('override 规则'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('所有段位'),
              value: _global,
              onChanged: (v) => setState(() => _global = v),
            ),
            if (!_global) ...[
              _rank('最低段位', _min, (v) => _min = v),
              _rank('最高段位', _max, (v) => _max = v),
            ],
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(hintText: 'maxVisits = 120'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
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
          try {
            final rule = GoEngineOverrideRule(
              id:
                  widget.rule?.id ??
                  DateTime.now().microsecondsSinceEpoch.toString(),
              displayName: _name.text.trim(),
              rankMin: _global ? null : _min,
              rankMax: _global ? null : _max,
              configText: _text.text,
            );
            GoEngineOverrideRule.validateList([rule]);
            Navigator.pop(context, rule);
          } catch (error) {
            setState(() => _error = '$error');
          }
        },
        child: const Text('保存规则'),
      ),
    ],
  );
}
