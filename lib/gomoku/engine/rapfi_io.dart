import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'rapfi_transport.dart';

RapfiTransport createRapfiTransport() =>
    Platform.isAndroid ? _AndroidTransport() : ProcessRapfiTransport();

class _AndroidTransport implements RapfiTransport {
  static const _methods = MethodChannel('easyplay/rapfi');
  static const _events = EventChannel('easyplay/rapfi/output');
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
class ProcessRapfiTransport implements RapfiTransport {
  ProcessRapfiTransport({this.executable = 'rapfi', this.workingDirectory});
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
        _lines.addError(StateError('Rapfi 已退出 ($code)'));
      }
    });
  }

  @override
  Future<void> send(String command) async {
    final process = _process;
    if (process == null) throw StateError('Rapfi 未启动');
    process.stdin.writeln(command);
    await process.stdin.flush();
  }

  @override
  Future<void> close() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
}
