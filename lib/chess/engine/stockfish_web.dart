import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'chess_engine.dart';

StockfishTransport createStockfishTransport() => _WorkerTransport();

class _WorkerTransport implements StockfishTransport {
  final _lines = StreamController<String>.broadcast();
  web.Worker? _worker;
  @override
  Stream<String> get lines => _lines.stream;
  @override
  Future<void> start() async {
    if (_worker != null) return;
    final url = Uri.parse(
      web.document.baseURI,
    ).resolve('stockfish/stockfish-19-lite-single.js');
    final worker = web.Worker(url.toString().toJS);
    _worker = worker;
    worker.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data != null && data.isA<JSString>()) {
        for (final line in (data as JSString).toDart.split('\n')) {
          _lines.add(line.trim());
        }
      }
    }).toJS;
    worker.onerror = ((web.Event _) {
      _lines.addError(StateError('Stockfish WASM 加载失败，请检查网络后重试'));
    }).toJS;
  }

  @override
  Future<void> send(String command) async {
    final worker = _worker;
    if (worker == null) throw StateError('Stockfish 未启动');
    worker.postMessage(command.toJS);
  }

  @override
  Future<void> close() async {
    _worker?.terminate();
    _worker = null;
  }
}
