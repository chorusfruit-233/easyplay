import '../game_session.dart';
import 'lan_game.dart';
import 'lan_protocol.dart';

class LanHostServer {
  LanHostServer({required this.authority, required this.token});
  final LanAuthority authority;
  final String token;
  int? get port => null;
  int get playerCount => 0;
  bool get started => false;
  Stream<int> get playerCounts => const Stream.empty();
  void startMatch() => throw UnsupportedError('当前平台不能开始房间');
  Future<void> start({String host = '0.0.0.0', int port = 8080}) async {
    throw UnsupportedError('Web 端不能创建局域网监听服务');
  }

  Future<void> close() async {}
}

class LanClientConnection {
  LanClientConnection(this.config);
  final GoConfig config;
  LanReplica? replica;
  Side? side;
  bool started = false;
  Stream<LanMessage> get messages => const Stream.empty();
  Stream<void> get disconnections => const Stream.empty();
  Future<void> reconnect() async =>
      throw UnsupportedError('当前平台没有可用的 Socket 传输');
  Future<void> connect(Uri uri, {required String token}) async {
    throw UnsupportedError('当前平台没有可用的 Socket 传输');
  }

  void send(LanMessage message) =>
      throw UnsupportedError('WebSocket not available');

  Future<void> disconnect() async {}

  Future<void> close() async {}
}
