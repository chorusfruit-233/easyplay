import '../../lan/message_transport.dart';
import 'battleship_room_coordinator.dart';

bool get battleshipLanHostingSupported => false;

Future<MessageTransport> connectBattleshipSocket(Uri uri) async =>
    throw UnsupportedError('当前平台不支持 LAN');

class BattleshipLanServer {
  BattleshipLanServer(BattleshipRoomCoordinator coordinator);
  int? get port => null;
  Future<void> start({String host = '0.0.0.0', int port = 8080}) async =>
      throw UnsupportedError('浏览器请加入 Android 房间');
  Future<void> close() async {}
}
