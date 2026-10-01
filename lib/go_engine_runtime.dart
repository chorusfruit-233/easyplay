import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'go_engine_profiles.dart';

/// CPU availability and recent engine logs; no model data crosses this page.
class GoEngineRuntimePage extends StatefulWidget {
  final GoEngineProfile profile;
  const GoEngineRuntimePage({super.key, required this.profile});
  @override
  State<GoEngineRuntimePage> createState() => _GoEngineRuntimePageState();
}

class _GoEngineRuntimePageState extends State<GoEngineRuntimePage> {
  static const _channel = MethodChannel('easyplay/katago');
  String _status = '检测中';
  String _logs = '';
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final result = _android
          ? await _channel.invokeMapMethod<String, Object?>(
              'backendPreflight',
              {'backend': 'cpu'},
            )
          : null;
      if (!mounted) return;
      setState(
        () => _status = _android
            ? (result?['runnable'] == true
                  ? 'CPU 引擎可用'
                  : '${result?['reason'] ?? 'CPU 引擎不可用'}')
            : kIsWeb
            ? 'Web 使用 WASM CPU，需要跨源隔离响应头。'
            : '此平台暂未提供原生引擎。',
      );
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    }
  }

  Future<void> _diagnostics() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'diagnostics',
      );
      if (mounted) {
        setState(
          () => _logs = const JsonEncoder.withIndent('  ').convert(result),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _logs = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.profile.name} · 运行检测')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_status),
        TextButton.icon(
          onPressed: _check,
          icon: const Icon(Icons.refresh),
          label: const Text('检查引擎'),
        ),
        if (_android)
          TextButton.icon(
            onPressed: _diagnostics,
            icon: const Icon(Icons.receipt_long),
            label: const Text('读取日志'),
          ),
        if (_logs.isNotEmpty) SelectableText(_logs),
      ],
    ),
  );
}
