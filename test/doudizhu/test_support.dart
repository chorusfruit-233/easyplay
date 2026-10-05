import 'dart:async';
import 'package:easyplay/lan/message_transport.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_coordinator.dart';
import 'package:easyplay/doudizhu/multiplayer/doudizhu_replica.dart';
import 'package:easyplay/doudizhu/doudizhu_model.dart';

Future<void> until(bool Function() predicate) async {
  final callSite = StackTrace.current;
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) {
      Error.throwWithStackTrace(
        TimeoutException('state did not arrive'),
        callSite,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class RecordingTransport implements MessageTransport {
  RecordingTransport(this.inner);
  final MessageTransport inner;
  final sent = <String>[];
  @override
  Stream<LanMessage> get messages => inner.messages;
  @override
  Stream<void> get disconnections => inner.disconnections;
  @override
  void send(LanMessage m) {
    sent.add(m.encode());
    inner.send(m);
  }

  @override
  Future<void> close() => inner.close();
}

Future<(DouDizhuReplica, RecordingTransport)> join(
  CardRoomCoordinator room,
  PlayerSeat seat,
) async {
  final (server, client) = MemoryTransport.pair();
  final recording = RecordingTransport(server);
  room.attach(recording, fixedSeat: seat);
  final replica = DouDizhuReplica();
  await replica.bind(
    client,
    token: seat == PlayerSeat.seat0 ? room.hostCredential : room.password,
  );
  replica.send('ready');
  await until(() => room.seats[seat.index]['ready'] == true);
  return (replica, recording);
}
