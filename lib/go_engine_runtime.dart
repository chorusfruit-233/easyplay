import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game_session.dart';
import 'go_ai_settings.dart';
import 'go_engine_config.dart';
import 'go_engine_profiles.dart';
import 'go_models.dart';

class GoEngineRuntimePage extends StatefulWidget {
  final GoEngineProfile profile;
  final GoAiSettings? settings;
  final GoConfig? config;
  const GoEngineRuntimePage({
    super.key,
    required this.profile,
    this.settings,
    this.config,
  });
  @override
  State<GoEngineRuntimePage> createState() => _GoEngineRuntimePageState();
}

class _GoEngineRuntimePageState extends State<GoEngineRuntimePage> {
  static const _channel = MethodChannel('easyplay/katago');
  Map<String, Object?>? _preflight;
  List<GoModelInfo> _models = [GoModelLibrary.bundledModel];
  late String _model =
      widget.settings?.modelId ??
      widget.profile.modelId ??
      GoModelLibrary.bundledId;
  late int _board = widget.config?.boardSize ?? 19;
  String? _id;
  String _state = 'idle';
  String _log = '';
  String? _error;
  bool _busy = false;
  Timer? _timer;
  bool _polling = false;
  int _generation = 0;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final models = await GoModelLibrary.available();
      final check = _android
          ? (await _channel
                .invokeMapMethod<String, Object?>('backendPreflight', {
                  'backend': widget.profile.backend.name,
                  'openclLibraryName': widget.profile.openclLibraryName,
                  'openclGpuIdx': widget.profile.openclGpuIdx ?? 0,
                }))!
          : <String, Object?>{
              'runnable':
                  kIsWeb && widget.profile.backend != GoEngineBackend.tflite,
              'reason': kIsWeb
                  ? '浏览器实际使用 WASM CPU；OpenCL 调优仅支持 Android。'
                  : '此平台暂未提供原生引擎。',
            };
      if (mounted)
        setState(() {
          _models = models;
          _preflight = check;
        });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _tune() async {
    final generation = ++_generation;
    _id = null;
    setState(() {
      _busy = true;
      _error = null;
      _state = 'starting';
    });
    try {
      var settings =
          (widget.settings ??
                  GoAiSettings(
                    engineProfileId: widget.profile.id,
                    humanModelId: widget.profile.humanModelId,
                    style: widget.profile.humanModelId == null
                        ? GoAiStyle.modern
                        : GoAiStyle.human,
                  ))
              .copyWith(modelId: _model);
      final main = await GoModelLibrary.byId(_model);
      if (main.isHumanModel) {
        settings = GoAiSettings.fromJson({
          ...settings.toJson(),
          'style': GoAiStyle.human.name,
          'humanModelId': null,
          'useBuiltinHumanStyle': true,
        });
      }
      final human = settings.usesHumanStyle && !settings.useBuiltinHumanStyle
          ? settings.humanModelId
          : null;
      GoModelCompatibility.validate(
        model: main,
        engine: widget.profile,
        humanModel: human == null ? null : await GoModelLibrary.byId(human),
        useBuiltinHumanStyle: settings.useBuiltinHumanStyle,
      );
      final config = (widget.config ?? const GoConfig()).copyWith(
        boardSize: _board,
      );
      final arguments = <String, Object?>{
        'model': await GoModelLibrary.load(_model),
        'modelFileName': main.fileName,
        if (human != null) 'humanModel': await GoModelLibrary.load(human),
        if (human != null)
          'humanModelFileName': (await GoModelLibrary.byId(human)).fileName,
        'config': await resolveKataGoConfig(
          config: config,
          settings: settings,
          engine: widget.profile,
        ),
        'boardSize': _board,
        'openclGpuIdx': widget.profile.openclGpuIdx ?? 0,
        'openclLibraryName': widget.profile.openclLibraryName,
      };
      if (!mounted || generation != _generation) return;
      final response = (await _channel.invokeMapMethod<String, Object?>(
        'openclTuningStart',
        arguments,
      ))!;
      final id = response['id'] as String;
      if (!mounted || generation != _generation) {
        await _channel.invokeMethod<Object?>('openclTuningCancel', {'id': id});
        return;
      }
      _id = id;
      setState(() => _state = response['status'] as String? ?? 'running');
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
      await _poll();
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() {
          _busy = false;
          _state = 'failed';
          _error = '$error';
        });
    }
  }

  Future<void> _poll() async {
    if (_polling || _id == null) return;
    final generation = _generation;
    _polling = true;
    try {
      final result = (await _channel.invokeMapMethod<String, Object?>(
        'openclTuningRead',
        {'id': _id},
      ))!;
      if (!mounted || generation != _generation) return;
      final state = result['status'] as String? ?? 'running';
      setState(() {
        _state = state;
        _log = (result['logs'] as List?)?.join('\n') ?? '';
        _error = result['error'] as String?;
      });
      if (state != 'running' && state != 'starting' && state != 'queued') {
        _timer?.cancel();
        setState(() => _busy = false);
        if (state == 'completed') {
          final current = await GoEngineLibrary.byId(widget.profile.id);
          final fingerprint = result['tuningId'] as String?;
          await GoEngineLibrary.save(
            current.copyWith(
              tuningState: GoOpenClTuningState.ready,
              snapshotKeys: {
                ...current.openclTunedSnapshotKeys,
                if (fingerprint != null) fingerprint,
              }.toList(),
            ),
          );
        }
      }
    } catch (error) {
      _timer?.cancel();
      if (mounted && generation == _generation)
        setState(() {
          _busy = false;
          _error = '$error';
        });
    } finally {
      _polling = false;
    }
  }

  Future<void> _cancel() async {
    _generation++;
    _timer?.cancel();
    try {
      if (_id != null)
        await _channel.invokeMethod<Object?>('openclTuningCancel', {'id': _id});
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
    if (mounted)
      setState(() {
        _busy = false;
        _state = 'cancelled';
      });
  }

  Future<void> _diagnostics() async {
    try {
      final data = await _channel.invokeMapMethod<String, Object?>(
        'diagnostics',
      );
      if (mounted)
        setState(() => _log = const JsonEncoder.withIndent('  ').convert(data));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    if (_busy && _id != null)
      unawaited(
        _channel
            .invokeMethod<Object?>('openclTuningCancel', {'id': _id})
            .then<void>((_) {}, onError: (Object _) {}),
      );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('引擎运行与调优')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.profile.name,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Text(
          _preflight == null
              ? '检测运行环境…'
              : _preflight!['runnable'] == true
              ? '运行环境可用'
              : '运行环境不可用',
        ),
        if (_preflight?['reason'] != null) Text('${_preflight!['reason']}'),
        if (_preflight?['devices'] is List) ...[
          const SizedBox(height: 12),
          for (final device in _preflight!['devices'] as List)
            Text(
              'GPU ${device['index']} · ${device['name']} · ${device['vendor']}',
            ),
        ],
        const SizedBox(height: 24),
        if (_android && widget.profile.backend == GoEngineBackend.opencl) ...[
          const Text('按主模型、人类模型、棋盘和 GPU 保存调优结果。更换模型或设备后需要重新调优；退出本页会停止正在进行的调优。'),
          const SizedBox(height: 20),
          const Text('调优主模型'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(_models.length),
            initialValue: _models.any((m) => m.id == _model)
                ? _model
                : GoModelLibrary.bundledId,
            isExpanded: true,
            items: _models
                .map(
                  (m) => DropdownMenuItem(
                    value: m.id,
                    child: Text(m.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (v) => setState(() => _model = v ?? _model),
          ),
          const SizedBox(height: 20),
          const Text('棋盘路数'),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _board,
            items: [9, 13, 19]
                .map((n) => DropdownMenuItem(value: n, child: Text('$n 路')))
                .toList(),
            onChanged: _busy
                ? null
                : (v) => setState(() => _board = v ?? _board),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy
                ? _cancel
                : _preflight?['runnable'] == true
                ? _tune
                : null,
            icon: Icon(_busy ? Icons.stop : Icons.speed),
            label: Text(_busy ? '停止调优' : '开始 OpenCL 调优'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          Text(switch (_state) {
            'completed' => '调优完成',
            'failed' => '调优失败',
            'cancelled' => '已取消',
            'running' || 'starting' || 'queued' => '调优中…',
            _ => '等待调优',
          }),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    try {
                      for (final key in (await GoEngineLibrary.byId(
                        widget.profile.id,
                      )).openclTunedSnapshotKeys) {
                        await _channel.invokeMethod<Map>('openclTuningReset', {
                          'tuningId': key,
                        });
                      }
                      final current = await GoEngineLibrary.byId(
                        widget.profile.id,
                      );
                      await GoEngineLibrary.save(
                        current.copyWith(
                          tuningState: GoOpenClTuningState.required,
                          snapshotKeys: [],
                        ),
                      );
                      if (mounted)
                        setState(() {
                          _state = 'idle';
                          _log = '已清除本机 OpenCL 调优缓存';
                        });
                    } catch (error) {
                      if (mounted) setState(() => _error = '$error');
                    }
                  },
            child: const Text('清除此引擎调优缓存'),
          ),
        ],
        if (_android)
          OutlinedButton(onPressed: _diagnostics, child: const Text('读取运行日志')),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        SelectableText(_log),
      ],
    ),
  );
}
