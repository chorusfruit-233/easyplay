import 'dart:convert';
import '../../lan/message_transport.dart';
import '../../lan/rtc_transport.dart';
import '../doudizhu_model.dart';
import 'card_room_coordinator.dart';
import 'doudizhu_replica.dart';

/// Each guest has an independent session/token. No cards occur in signaling.
class CardRtcInvitation {
  CardRtcInvitation({
    required this.roomId,
    required this.seat,
    required this.sessionId,
    required this.token,
    required this.sdp,
    required this.type,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();
  final String roomId, sessionId, token, sdp, type;
  final PlayerSeat seat;
  final DateTime createdAt;
  String encode() => jsonEncode({
    'game': 'doudizhu',
    'formatVersion': 1,
    'rulesVersion': 1,
    'protocolVersion': 1,
    'roomId': roomId,
    'seat': seat.index,
    'sessionId': sessionId,
    'token': token,
    'sdp': sdp,
    'type': type,
    'createdAt': createdAt.toIso8601String(),
  });
  CardRtcInvitation answer(String sdp) => CardRtcInvitation(
    roomId: roomId,
    seat: seat,
    sessionId: sessionId,
    token: token,
    sdp: sdp,
    type: 'answer',
    createdAt: createdAt,
  );
  static CardRtcInvitation decode(String text, {required String type}) {
    if (utf8.encode(text).length > 256 * 1024) {
      throw const FormatException('邀请过长');
    }
    final d = jsonDecode(text);
    if (d is! Map ||
        d['game'] != 'doudizhu' ||
        d['formatVersion'] != 1 ||
        d['protocolVersion'] != 1 ||
        d['rulesVersion'] != 1 ||
        d['type'] != type ||
        ![1, 2].contains(d['seat']) ||
        d['sdp'] is! String ||
        !(d['sdp'] as String).startsWith('v=0')) {
      throw const FormatException('斗地主邀请格式无效');
    }
    for (final field in ['roomId', 'sessionId', 'token']) {
      if (d[field] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(d[field] as String)) {
        throw const FormatException('邀请身份无效');
      }
    }
    final at = DateTime.tryParse(d['createdAt'] as String);
    if (at == null ||
        DateTime.now().difference(at) > const Duration(minutes: 30) ||
        at.difference(DateTime.now()) > const Duration(minutes: 2)) {
      throw const FormatException('邀请已过期');
    }
    return CardRtcInvitation(
      roomId: d['roomId'] as String,
      seat: PlayerSeat.values[d['seat'] as int],
      sessionId: d['sessionId'] as String,
      token: d['token'] as String,
      sdp: d['sdp'] as String,
      type: type,
      createdAt: at,
    );
  }
}

class CardRtcRoom {
  CardRtcRoom.host({this.iceServers})
    : coordinator = CardRoomCoordinator(password: cardSecret());
  CardRtcRoom.guest({this.iceServers}) : coordinator = null;
  final List<Map<String, Object?>>? iceServers;
  final CardRoomCoordinator? coordinator;
  final replica = DouDizhuReplica();
  final _peers = <PlayerSeat, RtcPeer>{};
  final _offers = <PlayerSeat, CardRtcInvitation>{};
  final _accepted = <String>{};
  RtcPeer? _guestPeer;
  bool _closed = false;
  bool get isHost => coordinator != null;
  Future<void> prepareHost() async {
    if (_closed || !isHost) throw StateError('房间已关闭');
    if (replica.connected) return;
    final (server, client) = MemoryTransport.pair();
    coordinator!.attach(server, fixedSeat: PlayerSeat.seat0);
    await replica.bind(client, token: coordinator!.hostCredential);
    replica.send('ready');
  }

  Future<String> offer(PlayerSeat seat) async {
    if (_closed || !isHost || seat == PlayerSeat.seat0) {
      throw StateError('座位无效');
    }
    if (coordinator!.seats[seat.index]['ai'] == true) {
      throw StateError('此座位由 AI 托管');
    }
    await _peers.remove(seat)?.close();
    final peer = RtcPeer(iceServers: iceServers);
    _peers[seat] = peer;
    final invitation = CardRtcInvitation(
      roomId: coordinator!.roomId,
      seat: seat,
      sessionId: cardSecret(),
      token: cardSecret(),
      sdp: await peer.createOffer(),
      type: 'offer',
    );
    if (_closed) {
      await peer.close();
      throw StateError('房间已关闭');
    }
    _offers[seat] = invitation;
    return invitation.encode();
  }

  Future<void> accept(String text) async {
    final answer = CardRtcInvitation.decode(text, type: 'answer');
    final offer = _offers[answer.seat];
    if (_closed ||
        offer == null ||
        answer.roomId != offer.roomId ||
        answer.sessionId != offer.sessionId ||
        answer.token != offer.token ||
        _accepted.contains(answer.sessionId)) {
      throw const FormatException('回应不属于当前邀请或已经使用');
    }
    _accepted.add(answer.sessionId);
    final peer = _peers[answer.seat]!;
    await peer.acceptAnswer(answer.sdp);
    final transport = await peer.transport;
    if (_closed) {
      await transport.close();
      return;
    }
    coordinator!.attach(
      transport,
      fixedSeat: answer.seat,
      invitationCredential: offer.token,
    );
  }

  Future<String> answer(String text) async {
    if (_closed || isHost) throw StateError('房间状态无效');
    final offer = CardRtcInvitation.decode(text, type: 'offer');
    if (replica.view != null &&
        (replica.view!.seat != offer.seat || replica.roomId != offer.roomId)) {
      throw const FormatException('重连邀请不属于原座位');
    }
    await _guestPeer?.close();
    final peer = RtcPeer(iceServers: iceServers);
    _guestPeer = peer;
    final answer = offer.answer(await peer.createAnswer(offer.sdp));
    // The answer must be exchanged before the DataChannel can open.
    peer.transport.then(
      (transport) async {
        if (_closed) {
          await transport.close();
          return;
        }
        try {
          await replica.bind(transport, token: offer.token);
          if (replica.view?.publicState.phase == DouDizhuPhase.waiting) {
            replica.send('ready');
          }
        } catch (_) {
          if (!_closed) {
            replica.reportError('连接失败，请交换新的邀请');
          }
        }
      },
      onError: (Object _) {
        if (!_closed) {
          replica.reportError('网络无法直连，请重试或切换 STUN');
        }
      },
    );
    return answer.encode();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await replica.close();
    await _guestPeer?.close();
    for (final peer in _peers.values) {
      await peer.close();
    }
    await coordinator?.close();
    _peers.clear();
    _offers.clear();
    _accepted.clear();
  }
}
