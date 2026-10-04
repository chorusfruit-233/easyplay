import 'xiangqi_engine.dart';

PikafishTransport createPikafishTransport() => _UnavailableTransport();

class _UnavailableTransport implements PikafishTransport {
  @override
  Stream<String> get lines => const Stream.empty();
  @override
  Future<void> start() async => throw UnsupportedError('当前平台不支持 Pikafish');
  @override
  Future<void> send(String command) async =>
      throw UnsupportedError('当前平台不支持 Pikafish');
  @override
  Future<void> close() async {}
}
