import 'message_transport.dart';

bool get rtcSupported => false;

class RtcPeer {
  RtcPeer({List<Map<String, Object?>>? iceServers});
  Stream<String> get states => const Stream.empty();
  String get state => '当前平台不支持浏览器 WebRTC';
  Future<MessageTransport> get transport =>
      Future.error(UnsupportedError(state));
  Future<String> createOffer() async => throw UnsupportedError(state);
  Future<String> createAnswer(String offer) async =>
      throw UnsupportedError(state);
  Future<void> acceptAnswer(String answer) async =>
      throw UnsupportedError(state);
  Future<String> candidateKind() async => 'unknown';
  Future<void> close() async {}
}
