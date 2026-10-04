import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'xiangqi_engine.dart';

PikafishTransport createPikafishTransport() =>
    Platform.isAndroid ? _AndroidTransport() : ProcessPikafishTransport();

class _AndroidTransport implements PikafishTransport {
  static const _methods = MethodChannel('easyplay/pikafish');
  static const _events = EventChannel('easyplay/pikafish/output');
  late final Stream<String> _lines = _events
      .receiveBroadcastStream()
      .cast<String>();
  @override
  Stream<String> get lines => _lines;
  @override
  Future<void> start() => _methods.invokeMethod<void>('start');
  @override
  Future<void> send(String command) =>
      _methods.invokeMethod<void>('send', {'command': command});
  @override
  Future<void> close() => _methods.invokeMethod<void>('close');
}

/// Also allows a real native UCI smoke test on developer Linux/macOS systems.
class ProcessPikafishTransport implements PikafishTransport {
  ProcessPikafishTransport({
    this.executable = 'pikafish',
    this.workingDirectory,
  });
  final String executable;
  final String? workingDirectory;
  final _lines = StreamController<String>.broadcast();
  Process? _process;
  @override
  Stream<String> get lines => _lines.stream;
  @override
  Future<void> start() async {
    if (_process != null) return;
    final process = await Process.start(
      executable,
      [],
      workingDirectory: workingDirectory,
    );
    _process = process;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_lines.add);
    process.stderr.drain<void>();
    process.exitCode.then((code) {
      if (identical(_process, process)) {
        _process = null;
        _lines.addError(StateError('Pikafish 已退出 ($code)'));
      }
    });
  }

  @override
  Future<void> send(String command) async {
    final process = _process;
    if (process == null) throw StateError('Pikafish 未启动');
    process.stdin.writeln(command);
    await process.stdin.flush();
  }

  @override
  Future<void> close() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    try {
      process.stdin.writeln('quit');
      await process.stdin.flush();
    } catch (_) {
      /* Already exited. */
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }
}
