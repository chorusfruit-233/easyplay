import 'dart:async';
import 'dart:convert';

import '../../lan/message_transport.dart';
import '../../lan/rtc_transport.dart';
import '../battleship.dart';
import 'battleship_replica.dart';
import 'battleship_room_coordinator.dart';

/// Signaling carries channel credentials and SDP, never a player's fleet.
class BattleshipRtcInvitation {
  BattleshipRtcInvitation({
    required this.roomId,
    required this.sessionId,
    required this.token,
    required this.sdp,
    required this.type,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? DateTime.now()).toUtc();

  final String roomId, sessionId, token, sdp, type;
  final DateTime createdAt;
  static const _fields = {
    'game',
    'formatVersion',
    'protocolVersion',
    'rulesVersion',
    'roomId',
    'seat',
    'sessionId',
    'token',
    'sdp',
    'type',
    'createdAt',
  };

  String encode() => jsonEncode({
    'game': 'battleship',
    'formatVersion': 1,
    'protocolVersion': 1,
    'rulesVersion': battleshipRulesVersion,
    'roomId': roomId,
    'seat': BattleshipSeat.player2.index,
    'sessionId': sessionId,
    'token': token,
    'sdp': sdp,
    'type': type,
    'createdAt': createdAt.toIso8601String(),
  });

  BattleshipRtcInvitation answer(String sdp) => BattleshipRtcInvitation(
    roomId: roomId,
    sessionId: sessionId,
    token: token,
    sdp: sdp,
    type: 'answer',
    createdAt: createdAt,
  );

  void validateAnswer(BattleshipRtcInvitation response) {
    if (response.type != 'answer' ||
        response.roomId != roomId ||
        response.sessionId != sessionId ||
        response.token != token ||
        response.createdAt != createdAt) {
      throw const FormatException('回应不属于当前邀请');
    }
  }

  static BattleshipRtcInvitation decode(String text, {required String type}) {
    if (utf8.encode(text).length > 256 * 1024) {
      throw const FormatException('邀请过长');
    }
    final data = jsonDecode(text);
    if (data is! Map ||
        data.length != _fields.length ||
        !data.keys.every(_fields.contains) ||
        data['game'] != 'battleship' ||
        data['formatVersion'] is! int ||
        data['formatVersion'] != 1 ||
        data['protocolVersion'] is! int ||
        data['protocolVersion'] != 1 ||
        data['rulesVersion'] is! int ||
        data['rulesVersion'] != battleshipRulesVersion ||
        data['type'] != type ||
        !['offer', 'answer'].contains(type) ||
        data['seat'] is! int ||
        data['seat'] != BattleshipSeat.player2.index ||
        data['sdp'] is! String ||
        !(data['sdp'] as String).startsWith('v=0')) {
      throw const FormatException('海战棋邀请格式无效');
    }
    for (final field in ['roomId', 'sessionId', 'token']) {
      final value = data[field];
      if (value is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
        throw const FormatException('邀请身份无效');
      }
    }
    final stamp = data['createdAt'];
    final createdAt = stamp is String ? DateTime.tryParse(stamp) : null;
    final now = DateTime.now();
    if (createdAt == null ||
        now.difference(createdAt) > const Duration(minutes: 30) ||
        createdAt.difference(now) > const Duration(minutes: 2)) {
      throw const FormatException('邀请已过期');
    }
    return BattleshipRtcInvitation(
      roomId: data['roomId'] as String,
      sessionId: data['sessionId'] as String,
      token: data['token'] as String,
      sdp: data['sdp'] as String,
      type: type,
      createdAt: createdAt,
    );
  }
}

/// A host replica shares the same private-view protocol as its remote guest.
class BattleshipRtcRoom {
  BattleshipRtcRoom.host({this.iceServers})
    : coordinator = BattleshipRoomCoordinator(password: battleshipSecret());
  BattleshipRtcRoom.guest({this.iceServers}) : coordinator = null;

  final List<Map<String, Object?>>? iceServers;
  final BattleshipRoomCoordinator? coordinator;
  final replica = BattleshipReplica();
  RtcPeer? _hostPeer, _guestPeer;
  BattleshipRtcInvitation? _offer;
  Future<void>? _preparing;
  final _accepted = <String>{};
  bool _closed = false;
  int _offerGeneration = 0, _answerGeneration = 0;

  bool get isHost => coordinator != null;

  Future<void> prepareHost() {
    if (_closed || !isHost) return Future.error(StateError('房间状态无效'));
    if (replica.connected) return Future.value();
    return _preparing ??= _bindHost().whenComplete(() => _preparing = null);
  }

  Future<void> _bindHost() async {
    final (server, client) = MemoryTransport.pair();
    coordinator!.attach(server, fixedSeat: BattleshipSeat.player1);
    try {
      await replica.bind(client, token: coordinator!.hostCredential);
    } catch (_) {
      await server.close();
      rethrow;
    }
  }

  Future<String> offer() async {
    if (_closed || !isHost) throw StateError('房间状态无效');
    if (coordinator!.seats[1]['connected'] == true) {
      throw StateError('对手仍然在线，请等待断线后再生成重连邀请');
    }
    final generation = ++_offerGeneration;
    _offer = null;
    await prepareHost();
    if (_closed || generation != _offerGeneration) {
      throw StateError('邀请已被替换');
    }
    if (coordinator!.seats[1]['connected'] == true) {
      throw StateError('对手仍然在线，请等待断线后再生成重连邀请');
    }
    await _hostPeer?.close();
    final peer = RtcPeer(iceServers: iceServers);
    _hostPeer = peer;
    try {
      final sdp = await peer.createOffer();
      if (_closed || generation != _offerGeneration) {
        throw StateError('邀请已被替换');
      }
      final invitation = BattleshipRtcInvitation(
        roomId: coordinator!.roomId,
        sessionId: battleshipSecret(),
        token: battleshipSecret(),
        sdp: sdp,
        type: 'offer',
      );
      _offer = invitation;
      return invitation.encode();
    } catch (_) {
      await peer.close();
      if (identical(_hostPeer, peer)) _hostPeer = null;
      rethrow;
    }
  }

  Future<void> accept(String text) async {
    if (_closed || !isHost) throw StateError('房间状态无效');
    final answer = BattleshipRtcInvitation.decode(text, type: 'answer');
    final offer = _offer;
    final peer = _hostPeer;
    if (offer == null ||
        peer == null ||
        coordinator!.seats[1]['connected'] == true ||
        _accepted.contains(answer.sessionId)) {
      throw const FormatException('回应不属于当前邀请或已经使用');
    }
    offer.validateAnswer(answer);
    _accepted.add(answer.sessionId);
    try {
      await peer.acceptAnswer(answer.sdp);
      final transport = await peer.transport;
      if (_closed || !identical(_hostPeer, peer) || !identical(_offer, offer)) {
        await transport.close();
        throw StateError('邀请已被替换');
      }
      coordinator!.attach(
        transport,
        fixedSeat: BattleshipSeat.player2,
        invitationCredential: offer.token,
      );
    } catch (_) {
      await peer.close();
      rethrow;
    }
  }

  Future<String> answer(String text) async {
    if (_closed || isHost) throw StateError('房间状态无效');
    final offer = BattleshipRtcInvitation.decode(text, type: 'offer');
    if (replica.roomId != null && replica.roomId != offer.roomId) {
      throw const FormatException('重连邀请不属于原房间');
    }
    if (replica.connected) throw StateError('仍然连接房间，请在断线后重连');
    final generation = ++_answerGeneration;
    await _guestPeer?.close();
    if (_closed || generation != _answerGeneration) {
      throw StateError('邀请已被替换');
    }
    final peer = RtcPeer(iceServers: iceServers);
    _guestPeer = peer;
    try {
      final sdp = await peer.createAnswer(offer.sdp);
      if (_closed || generation != _answerGeneration) {
        throw StateError('邀请已被替换');
      }
      // Pin the welcome to the room authenticated in the signaling wrapper.
      replica.roomId = offer.roomId;
      unawaited(_bindGuest(peer, offer));
      return offer.answer(sdp).encode();
    } catch (_) {
      await peer.close();
      if (identical(_guestPeer, peer)) _guestPeer = null;
      rethrow;
    }
  }

  Future<void> _bindGuest(RtcPeer peer, BattleshipRtcInvitation offer) async {
    try {
      final transport = await peer.transport;
      if (_closed || !identical(_guestPeer, peer)) {
        await transport.close();
        return;
      }
      await replica.bind(transport, token: offer.token);
    } catch (_) {
      if (!_closed && identical(_guestPeer, peer)) {
        replica.reportError('连接失败，请交换新的邀请或切换 STUN');
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _offerGeneration++;
    _answerGeneration++;
    await replica.close();
    await _guestPeer?.close();
    await _hostPeer?.close();
    await coordinator?.close();
    _hostPeer = null;
    _guestPeer = null;
    _offer = null;
    _accepted.clear();
  }
}
