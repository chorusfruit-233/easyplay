import 'dart:convert';
import 'package:file_picker/file_picker.dart';
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

  GoModelInfo? get _mainModel =>
      _models.where((m) => m.id == _modelId).firstOrNull;
  GoModelInfo? get _humanModel =>
      _models.where((m) => m.id == _humanId).firstOrNull;

  /// Badges follow the reference layout: whether the network is a human-style
  /// one, whether it is the standard kind, and whether it is already on device.
  List<_Badge> _badgesFor(GoModelInfo? model) {
    if (model == null) return const [];
    return [
      if (model.isHumanModel)
        const _Badge('人类棋风', _BadgeTone.accent)
      else
        const _Badge('普通', _BadgeTone.muted),
      const _Badge('标准', _BadgeTone.warn),
      if (model.bundled)
        const _Badge('内置', _BadgeTone.ok)
      else
        const _Badge('已下载', _BadgeTone.ok),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final backendDescription = switch (_backend) {
      GoEngineBackend.cpu => '兼容性最好，使用标准 KataGo 模型。',
      GoEngineBackend.opencl => '使用 GPU / OpenCL 加速，支持标准 KataGo 模型。',
      GoEngineBackend.tflite => '需要设备端 LiteRT 运行库，当前构建尚未包含。',
    };

    return Form(
      key: _form,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(
                '引擎名称',
                TextFormField(
                  controller: _name,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入名称' : null,
                ),
              ),
              _sectionTitle('主模型'),
              _pickerCard(
                title: _mainModel?.name ?? '内置',
                badges: _badgesFor(_mainModel),
                subtitle: _mainModel?.fileName,
                onTap: _pickMainModel,
              ),
              _sectionTitle('人类棋风模型'),
              _pickerCard(
                title: _humanModel?.name ?? '点击选择',
                badges: _badgesFor(_humanModel),
                subtitle: _humanModel?.fileName,
                leadingIcon: _humanModel == null ? Icons.add : null,
                onTap: _pickHumanModel,
              ),
              if (_humanModel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '这个引擎已配置人类棋风模型，因此段位难度会使用人类棋风下法。'
                    'Max 只使用主模型。',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              _sectionTitle('运行方式'),
              _pickerCard(
                title: _backend.label,
                subtitle: backendDescription,
                onTap: _pickBackend,
              ),
              if (_backend == GoEngineBackend.opencl) ...[
                _sectionTitle('OpenCL 调优'),
                _tuningRow('主模型', widget.profile?.openclTuningState),
                _tuningRow('人类模型', widget.profile?.openclTuningState),
                const SizedBox(height: 4),
                Text(
                  '设备 OpenCL 驱动：${_library.text.trim().isEmpty ? '自动' : _library.text.trim()}'
                  '　GPU ${_gpu.text.trim().isEmpty ? '0' : _gpu.text.trim()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              _sectionTitle('配置'),
              _pickerCard(
                title: _cfg.text.trim().isEmpty ? '内置配置' : '自定义配置',
                badges: [
                  if (_cfg.text.trim().isEmpty)
                    const _Badge('内置', _BadgeTone.ok)
                  else
                    const _Badge('自定义', _BadgeTone.accent),
                ],
                onTap: _editConfig,
              ),
              _sectionTitle('Override 规则'),
              _pickerCard(
                title: '${_normal.length + _human.length} 条规则',
                subtitle: [
                  if (_normal.isNotEmpty) '普通棋风 ${_normal.length} 条',
                  if (_human.isNotEmpty) '人类棋风 ${_human.length} 条',
                ].join(' · '),
                onTap: _editRules,
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: colors.error)),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('保存'),
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

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  /// A tappable card standing in for a secondary screen, as in the reference
  /// layout: the sheet itself stays a short list of summaries.
  Widget _pickerCard({
    required String title,
    required VoidCallback onTap,
    List<_Badge> badges = const [],
    String? subtitle,
    IconData? leadingIcon,
  }) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (badges.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(spacing: 6, runSpacing: 4, children: badges),
                    ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );

  /// Tuning is per network, so the main and human models are listed separately.
  /// Re-tuning itself is not wired up yet.
  Widget _tuningRow(String label, GoOpenClTuningState? state) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          state?.label ?? GoOpenClTuningState.unknown.label,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _retune,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重调'),
        ),
      ],
    ),
  );

  Future<void> _retune() async {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('OpenCL 调优尚未接入，暂不能重新调优')));
  }

  Future<void> _pickBackend() async {
    final picked = await showModalBottomSheet<GoEngineBackend>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: RadioGroup<GoEngineBackend>(
          groupValue: _backend,
          onChanged: (v) => Navigator.pop(sheetContext, v ?? _backend),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final value in GoEngineBackend.values)
                RadioListTile<GoEngineBackend>(
                  value: value,
                  title: Text(value.label),
                  subtitle: Text(switch (value) {
                    GoEngineBackend.cpu => '兼容性最好，使用标准 KataGo 模型。',
                    GoEngineBackend.opencl =>
                      '使用 GPU / OpenCL 加速，支持标准 KataGo 模型。',
                    GoEngineBackend.tflite => '需要设备端 LiteRT 运行库，当前构建尚未包含。',
                  }),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _backend = picked);
  }

  Future<void> _pickMainModel() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('在新局设置中选择'),
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            for (final model in _models)
              ListTile(
                title: Text(model.name),
                subtitle: Text('${model.kind.label} · ${model.fileName}'),
                trailing: model.id == _modelId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, model.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _modelId = picked.isEmpty ? null : picked);
    }
  }

  Future<void> _pickHumanModel() async {
    final candidates = _models.where((m) => m.isHumanModel).toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('不使用'),
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            for (final model in candidates)
              ListTile(
                title: Text(model.name),
                subtitle: Text(model.fileName),
                trailing: model.id == _humanId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, model.id),
              ),
            if (candidates.isEmpty)
              const ListTile(
                title: Text('尚无人类棋风模型'),
                subtitle: Text('请先在 AI 模型中下载人类棋风网络'),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _humanId = picked.isEmpty ? null : picked);
    }
  }

  Future<void> _editConfig() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('自定义配置', style: TextStyle(fontWeight: FontWeight.w600)),
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 12),
              child: Text(
                '合并顺序：内置参数 → 自定义 cfg → 全局/段位规则 → 最终参数覆盖。'
                '棋盘、规则和人类段位以新局设置为准。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            TextFormField(
              controller: _cfg,
              minLines: 6,
              maxLines: 14,
              validator: _configValidator,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: _importConfig,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('导入 .cfg'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, 'ok'),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (text != null && mounted) setState(() {});
  }

  Future<void> _editRules() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Override 规则',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              _rules(false),
              _rules(true),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

/// Small coloured pill used on the picker cards.
enum _BadgeTone { muted, accent, warn, ok }

class _Badge extends StatelessWidget {
  final String text;
  final _BadgeTone tone;
  const _Badge(this.text, this.tone);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      _BadgeTone.muted => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
      _BadgeTone.accent => (colors.primaryContainer, colors.onPrimaryContainer),
      _BadgeTone.warn => (colors.tertiaryContainer, colors.onTertiaryContainer),
      _BadgeTone.ok => (colors.secondaryContainer, colors.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
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
