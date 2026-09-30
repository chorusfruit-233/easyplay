import 'chess_lan_game.dart';
import '../game_session.dart';
import '../draughts/draughts_variant.dart';
import 'draughts_lan_game.dart';
import 'lan_game.dart';
import 'lan_protocol.dart';

class LanHostServer {
  // Preserve the existing named Go constructor parameter for callers.
  LanHostServer({
    LanAuthority? authority,
    this.draughtsAuthority,
    this.chessAuthority,
    required this.token,
  })
    // ignore: prefer_initializing_formals
    : _authority = authority;
  final LanAuthority? _authority;
  LanAuthority get authority => _authority!;
  final DraughtsAuthority? draughtsAuthority;
  final ChessAuthority? chessAuthority;
  final String token;
  int get seq => chessAuthority?.seq ?? draughtsAuthority?.seq ?? authority.seq;
  bool get gameOver =>
      chessAuthority?.session.gameOver ??
      draughtsAuthority?.session.gameOver ??
      authority.session.gameOver;
  LanMessage submit(Side side, LanMessage request) =>
      chessAuthority?.submit(side, request) ??
      draughtsAuthority?.submit(side, request) ??
      authority.submit(side, request);
  LanMessage sync(LanMessage request) =>
      chessAuthority?.sync(request) ??
      draughtsAuthority?.sync(request) ??
      authority.sync(request);
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
  LanClientConnection(this.config) : draughtsVariant = null, isChess = false;
  LanClientConnection.draughts(DraughtsVariant variant)
    : config = const GoConfig(),
      draughtsVariant = variant,
      isChess = false;
  LanClientConnection.chess()
    : config = const GoConfig(),
      draughtsVariant = null,
      isChess = true;
  final bool isChess;
  final GoConfig config;
  final DraughtsVariant? draughtsVariant;
  LanReplica? replica;
  DraughtsLanReplica? draughtsReplica;
  ChessLanReplica? chessReplica;
  Side? side;
  bool started = false;
  int get seq => chessReplica?.seq ?? draughtsReplica?.seq ?? replica?.seq ?? 0;
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
