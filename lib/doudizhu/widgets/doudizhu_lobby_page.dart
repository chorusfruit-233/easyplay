import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../lan/message_transport.dart';
import '../../lan/lan_scanner.dart';
import '../../lan/lan_addresses.dart';
import '../../lan/rtc_transport.dart';
import '../../lan/rtc_ice_config.dart';
import '../doudizhu.dart';
import '../doudizhu_match_controller.dart';
import '../multiplayer/card_room_coordinator.dart';
import '../multiplayer/card_lan.dart';
import '../multiplayer/card_rtc_room.dart';
import '../multiplayer/doudizhu_replica.dart';
import 'doudizhu_game_page.dart';

class DouDizhuLobbyPage extends StatefulWidget {
  const DouDizhuLobbyPage({super.key, this.rtc = false, this.initialOrigin});
  final bool rtc;
  final Uri? initialOrigin;
  @override
  State<DouDizhuLobbyPage> createState() => _DouDizhuLobbyPageState();
}

class _DouDizhuLobbyPageState extends State<DouDizhuLobbyPage> {
  final _address = TextEditingController(),
      _password = TextEditingController(),
      _signal = TextEditingController(),
      _customStun = TextEditingController();
  CardRoomCoordinator? _coordinator;
  CardLanServer? _server;
  CardRtcRoom? _rtcRoom;
  DouDizhuReplica? _replica;
  bool _busy = false, _inGame = false, _closing = false;
  String? _error, _outgoing;
  String _stun = 'domestic';
  PlayerSeat _inviteSeat = PlayerSeat.seat1;
  List<LanEndpoint> _found = [];
  List<String> _addresses = [];
  bool get _host => _coordinator != null;
  @override
  void initState() {
    super.initState();
    if (widget.initialOrigin != null) {
      _address.text = widget.initialOrigin!.origin;
    }
  }

  List<Map<String, Object?>> get _ice => switch (_stun) {
    'none' => [],
    'international' => rtcStunServers(rtcInternationalStunUrls),
    'custom' => parseRtcStunServers(_customStun.text),
    _ => rtcStunServers(rtcDomesticStunUrls),
  };
  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError ? e.message.toString() : '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _observe(DouDizhuReplica replica) {
    _replica?.removeListener(_changed);
    _replica = replica;
    replica.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (!mounted || _closing) return;
    setState(() {});
    final phase = _replica?.view?.publicState.phase;
    if (!_inGame && phase != null && phase != DouDizhuPhase.waiting) {
      _inGame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openGame());
    }
  }

  Future<void> _openGame() async {
    if (!mounted || _replica == null) return;
    final controller = DouDizhuMatchController.network(_replica!);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DouDizhuGamePage(controller: controller),
      ),
    );
    controller.dispose();
    // Returning to the lobby is useful for manually renegotiating a lost peer.
    if (mounted) setState(() {});
  }

  Future<void> _create() => _run(() async {
    if (widget.rtc) {
      final room = CardRtcRoom.host(iceServers: _ice);
      try {
        await room.prepareHost();
        if (!mounted || _closing) {
          await room.close();
          return;
        }
        _rtcRoom = room;
        _coordinator = room.coordinator;
        _observe(room.replica);
      } catch (_) {
        await room.close();
        rethrow;
      }
    } else {
      if (_password.text.trim().isEmpty) throw StateError('请先设置房间口令');
      final coordinator = CardRoomCoordinator(password: _password.text.trim());
      final server = CardLanServer(coordinator);
      final replica = DouDizhuReplica();
      try {
        await server.start();
        final addresses = await lanLocalAddresses();
        final (host, client) = MemoryTransport.pair();
        coordinator.attach(host, fixedSeat: PlayerSeat.seat0);
        await replica.bind(client, token: coordinator.hostCredential);
        replica.send('ready');
        await replica.waitForSnapshot((r) => r.seats[0]['ready'] == true);
        if (!mounted || _closing) {
          await replica.close();
          await coordinator.close();
          await server.close();
          return;
        }
        _coordinator = coordinator;
        _server = server;
        _addresses = addresses;
        _observe(replica);
      } catch (_) {
        await replica.close();
        await coordinator.close();
        await server.close();
        rethrow;
      }
    }
  });
  Future<void> _join() => _run(() async {
    if (_password.text.trim().isEmpty) throw StateError('请输入房间口令');
    var raw = _address.text.trim();
    if (!raw.contains('://')) raw = 'ws://$raw';
    var uri = Uri.parse(raw);
    if (uri.scheme == 'http') uri = uri.replace(scheme: 'ws');
    if (uri.scheme == 'https') uri = uri.replace(scheme: 'wss');
    if (!['ws', 'wss'].contains(uri.scheme) || uri.host.isEmpty) {
      throw StateError('地址格式为 192.168.1.10:8080');
    }
    final replica = _replica ?? DouDizhuReplica();
    Future<void> connect() async => replica.bind(
      await connectCardSocket(uri),
      token: _password.text.trim(),
    );
    replica.reconnect = connect;
    _observe(replica);
    await connect();
    if (replica.view!.publicState.phase == DouDizhuPhase.waiting) {
      replica.send('ready');
    }
    _observe(replica);
  });
  Future<void> _offer() => _run(() async {
    if (_rtcRoom == null || !_host) throw StateError('请先创建房间');
    _outgoing = null;
    _signal.clear();
    _outgoing = await _rtcRoom!.offer(_inviteSeat);
  });
  Future<void> _answer() => _run(() async {
    _outgoing = null;
    _rtcRoom ??= CardRtcRoom.guest(iceServers: _ice);
    _observe(_rtcRoom!.replica);
    _outgoing = await _rtcRoom!.answer(_signal.text.trim());
  });
  Future<void> _accept() => _run(() async {
    await _rtcRoom!.accept(_signal.text.trim());
  });
  @override
  void dispose() {
    _closing = true;
    _replica?.removeListener(_changed);
    if (_rtcRoom != null) {
      unawaited(_rtcRoom!.close());
    } else {
      unawaited(_replica?.close());
      unawaited(_coordinator?.close());
    }
    unawaited(_server?.close());
    for (final c in [_address, _password, _signal, _customStun]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final replica = _replica;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rtc ? '斗地主 · WebRTC 房间' : '斗地主 · 局域网房间'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('熟人三人房间；支持两名真人加一名房主本地 AI。房主退出后房间关闭，不保存牌谱。'),
          const SizedBox(height: 16),
          if (widget.rtc) ...[
            const Text(
              '分别向玩家 2、玩家 3 发送邀请，并粘贴各自的回应。断线时只为原座位重新交换邀请。无 TURN 时部分网络无法直连。',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _stun,
              decoration: const InputDecoration(labelText: '连接选项'),
              items: const [
                DropdownMenuItem(value: 'domestic', child: Text('国内 STUN')),
                DropdownMenuItem(
                  value: 'international',
                  child: Text('国际 STUN'),
                ),
                DropdownMenuItem(value: 'none', child: Text('同网连接（关闭 STUN）')),
                DropdownMenuItem(value: 'custom', child: Text('自定义 STUN')),
              ],
              onChanged: replica == null
                  ? (s) => setState(() => _stun = s!)
                  : null,
            ),
            if (_stun == 'custom')
              TextField(
                controller: _customStun,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'STUN 地址，每行一个'),
              ),
            const SizedBox(height: 12),
            if (replica == null)
              FilledButton(
                onPressed: _busy || !rtcSupported ? null : _create,
                child: const Text('创建三人房间'),
              ),
            if (_host) ...[
              DropdownButton<PlayerSeat>(
                value: _inviteSeat,
                items: [
                  for (final s in [PlayerSeat.seat1, PlayerSeat.seat2])
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (s) => setState(() => _inviteSeat = s!),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _offer,
                child: const Text('为此座位生成邀请 / 重连邀请'),
              ),
            ],
            TextField(
              controller: _signal,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _host ? '粘贴对应座位的回应' : '粘贴房主邀请（重连须为原座位）',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : _host
                  ? _accept
                  : _answer,
              child: Text(_host ? '接收回应' : '加入 / 重连并生成回应'),
            ),
            if (_outgoing != null) ...[
              const SizedBox(height: 12),
              SelectableText(_outgoing!, maxLines: 4),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => Clipboard.setData(ClipboardData(text: _outgoing!)),
                icon: const Icon(Icons.copy),
                label: Text(_host ? '复制邀请，发给对应玩家' : '复制回应，发给房主'),
              ),
            ],
          ] else ...[
            if (!_host)
              TextField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: '主机地址',
                  hintText: '192.168.1.10:8080',
                ),
              ),
            TextField(
              controller: _password,
              enabled: replica == null,
              decoration: const InputDecoration(labelText: '房间口令'),
            ),
            const SizedBox(height: 12),
            if (replica == null)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (cardLanHostingSupported)
                    FilledButton(
                      onPressed: _busy ? null : _create,
                      child: const Text('创建房间'),
                    ),
                  OutlinedButton(
                    onPressed: _busy ? null : _join,
                    child: const Text('加入房间'),
                  ),
                  if (cardLanHostingSupported)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              _found = (await scanLan())
                                  .where((r) => r.game == 'doudizhu')
                                  .toList();
                            }),
                      child: const Text('扫描局域网'),
                    ),
                ],
              ),
            for (final room in _found)
              ListTile(
                title: Text(room.address),
                subtitle: Text('斗地主 · ${room.players}/3'),
                onTap: () => setState(() => _address.text = room.address),
              ),
            if (_host) ...[
              SelectableText('房间口令：${_password.text}'),
              for (final address in _addresses)
                SelectableText('http://$address:${_server?.port}'),
              const Text('其他设备打开主机网页可快捷加入，也可以在 App 内输入地址和口令。'),
            ],
            if (replica != null && !replica.connected && !_host)
              OutlinedButton(
                onPressed: _busy ? null : _join,
                child: const Text('凭原身份重新连接'),
              ),
          ],
          const SizedBox(height: 20),
          if (replica != null) ...[
            for (var i = 0; i < replica.seats.length; i++)
              ListTile(
                leading: Icon(
                  replica.seats[i]['ai'] == true
                      ? Icons.smart_toy_outlined
                      : Icons.person_outline,
                ),
                title: Text(PlayerSeat.values[i].label),
                subtitle: Text(
                  replica.seats[i]['ai'] == true
                      ? '本地 AI · 已准备'
                      : replica.seats[i]['connected'] == true
                      ? replica.seats[i]['ready'] == true
                            ? '已连接 · 已准备'
                            : '已连接 · 等待准备'
                      : replica.seats[i]['occupied'] == true
                      ? '离线 · 保留座位，等待重连'
                      : '空座位',
                ),
                trailing:
                    _host &&
                        i > 0 &&
                        replica.seats[i]['occupied'] != true &&
                        replica.view?.publicState.phase == DouDizhuPhase.waiting
                    ? TextButton(
                        onPressed: () =>
                            _coordinator!.setAi(PlayerSeat.values[i], true),
                        child: const Text('AI 补位'),
                      )
                    : _host &&
                          replica.seats[i]['ai'] == true &&
                          replica.view?.publicState.phase ==
                              DouDizhuPhase.waiting
                    ? TextButton(
                        onPressed: () =>
                            _coordinator!.setAi(PlayerSeat.values[i], false),
                        child: const Text('等待真人'),
                      )
                    : null,
              ),
            if (replica.view?.publicState.phase == DouDizhuPhase.waiting) ...[
              if (replica.connected)
                OutlinedButton(
                  onPressed: () => replica.send('ready'),
                  child: const Text('准备'),
                ),
              if (_host)
                FilledButton(
                  onPressed: _coordinator!.canStart
                      ? () => replica.send('start')
                      : null,
                  child: const Text('三人准备后开始'),
                ),
            ] else
              FilledButton(onPressed: _openGame, child: const Text('返回对局')),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error != null || replica?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error ?? replica!.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
