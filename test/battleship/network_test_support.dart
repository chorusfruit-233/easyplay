import 'dart:async';

import 'package:easyplay/battleship/battleship.dart';
import 'package:easyplay/battleship/multiplayer/battleship_replica.dart';
import 'package:easyplay/battleship/multiplayer/battleship_room_coordinator.dart';
import 'package:easyplay/lan/lan_protocol.dart';
import 'package:easyplay/lan/message_transport.dart';

Future<void> until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('等待房间状态更新超时');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class ObservedTransport implements MessageTransport {
  ObservedTransport(this.inner);
  final MessageTransport inner;
  final sent = <LanMessage>[];
  @override
  Stream<LanMessage> get messages => inner.messages;
  @override
  Stream<void> get disconnections => inner.disconnections;
  @override
  void send(LanMessage message) {
    sent.add(message);
    inner.send(message);
  }

  @override
  Future<void> close() => inner.close();
}

Future<(BattleshipReplica, ObservedTransport)> join(
  BattleshipRoomCoordinator room, {
  bool host = false,
  BattleshipReplica? replica,
  String? token,
}) async {
  final (server, client) = MemoryTransport.pair();
  room.attach(server, fixedSeat: host ? BattleshipSeat.player1 : null);
  final observed = ObservedTransport(client);
  final player = replica ?? BattleshipReplica();
  await player.bind(
    observed,
    token: token ?? (host ? room.hostCredential : room.password),
  );
  return (player, observed);
}

Future<void> submit(
  BattleshipRoomCoordinator room,
  BattleshipReplica player,
  String action, [
  Map<String, Object?> payload = const {},
]) async {
  await until(() => player.seq == room.seq);
  final old = room.seq;
  player.send(action, payload);
  await until(() => room.seq > old);
  await until(() => player.seq == room.seq);
}

Future<void> begin(
  BattleshipRoomCoordinator room,
  BattleshipReplica host,
  BattleshipReplica guest,
) async {
  await submit(room, host, 'start');
  await until(() => host.seq == guest.seq);
  host.send('randomize');
  guest.send('randomize');
  await until(
    () => host.view!.ownFleet.length == 5 && guest.view!.ownFleet.length == 5,
  );
  await until(() => host.seq == room.seq && guest.seq == room.seq);
  host.send('ready');
  guest.send('ready');
  await until(() => room.session.phase == BattleshipPhase.playing);
  await until(() => host.seq == room.seq && guest.seq == room.seq);
}
