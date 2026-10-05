import '../../lan/message_transport.dart';
import 'card_room_coordinator.dart';

bool get cardLanHostingSupported => false;
Future<MessageTransport> connectCardSocket(Uri uri) async =>
    throw UnsupportedError('当前平台不支持 LAN');

class CardLanServer {
  CardLanServer(CardRoomCoordinator coordinator);
  int? get port => null;
  Future<void> start({String host = '0.0.0.0', int port = 8080}) async =>
      throw UnsupportedError('浏览器请加入 Android 房间');
  Future<void> close() async {}
}
