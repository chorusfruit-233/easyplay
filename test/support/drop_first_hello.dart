import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/message_transport.dart';

/// Reproduces an open RTC channel losing its first application handshake.
class DropFirstHelloTransport implements HelloRetryTransport {
  DropFirstHelloTransport(this.inner);
  final MessageTransport inner;
  LanMessage? hello;
  int attempts = 0;
  @override
  bool get supportsHelloRetry => true;
  @override
  Stream<LanMessage> get messages => inner.messages;
  @override
  Stream<void> get disconnections => inner.disconnections;
  @override
  Future<void> close() => inner.close();
  @override
  void send(LanMessage message) {
    if (message.type == LanMessageType.hello ||
        (message.type == LanMessageType.card &&
            message.body['action'] == 'hello')) {
      attempts++;
      if (hello == null) {
        hello = message;
        return;
      }
    }
    inner.send(message);
  }
}
