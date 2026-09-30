import 'chess_engine.dart';

StockfishTransport createStockfishTransport() => _UnavailableTransport();

class _UnavailableTransport implements StockfishTransport {
  @override
  Stream<String> get lines => const Stream.empty();
  @override
  Future<void> start() async => throw UnsupportedError('当前平台不支持 Stockfish');
  @override
  Future<void> send(String command) async =>
      throw UnsupportedError('当前平台不支持 Stockfish');
  @override
  Future<void> close() async {}
}
