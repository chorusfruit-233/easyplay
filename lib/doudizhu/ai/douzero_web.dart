import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'douzero_runtime.dart';

DouZeroRuntime createDouZeroRuntime() => _WorkerRuntime();

class _WorkerRuntime implements DouZeroRuntime {
  web.Worker? _worker;
  final _pending = <int, Completer<Float32List>>{};
  int _nextId = 0;
  Timer? _idle;
  @override
  bool get supported => true;

  web.Worker _start() {
    if (_worker case final worker?) return worker;
    final url = Uri.parse(web.document.baseURI).resolve('douzero/worker.js');
    final worker = web.Worker(url.toString().toJS);
    _worker = worker;
    worker.onmessage = ((web.MessageEvent event) {
      if (!identical(_worker, worker)) return;
      final data = event.data as JSObject;
      final id = data.getProperty<JSNumber>('id'.toJS).toDartInt;
      final completer = _pending.remove(id);
      if (completer == null) return;
      if (data.hasProperty('error'.toJS).toDart) {
        completer.completeError(StateError('DouZero model inference failed'));
        _close();
        return;
      } else {
        completer.complete(
          data.getProperty<JSFloat32Array>('values'.toJS).toDart,
        );
      }
      if (_pending.isEmpty) {
        _idle = Timer(const Duration(minutes: 1), _close);
      }
    }).toJS;
    worker.onerror = ((web.Event _) {
      if (identical(_worker, worker)) _close();
    }).toJS;
    return worker;
  }

  @override
  Future<Float32List> score(String role, Float32List x, Float32List z) async {
    _idle?.cancel();
    final worker = _start();
    final id = ++_nextId;
    final completer = Completer<Float32List>();
    _pending[id] = completer;
    final request = JSObject()
      ..setProperty('id'.toJS, id.toJS)
      ..setProperty('role'.toJS, role.toJS)
      ..setProperty('x'.toJS, x.toJS)
      ..setProperty('z'.toJS, z.toJS);
    worker.postMessage(request);
    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _close();
        throw TimeoutException('DouZero inference timed out');
      },
    );
  }

  void _close() {
    _idle?.cancel();
    _idle = null;
    _worker?.terminate();
    _worker = null;
    for (final pending in _pending.values) {
      pending.completeError(StateError('DouZero worker closed'));
    }
    _pending.clear();
  }

  @override
  Future<void> reset() async => _close();
}
