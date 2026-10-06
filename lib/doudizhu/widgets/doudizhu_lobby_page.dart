import '../../ui/app_layout.dart';
import 'dart:async';
import 'dart:math';
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

class DouDizhuLanLobbyPage extends StatelessWidget {
  const DouDizhuLanLobbyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('斗地主联机')),
    body: AppPageList(
      children: [
        const Text('经典三人斗地主 · 支持房主本地 AI 补位'),
        const SizedBox(height: 16),
        if (rtcSupported)
          Card(
            child: ListTile(
              leading: const Icon(Icons.public),
              title: const Text('互联网联机（WebRTC）'),
              subtitle: const Text('交换邀请与回应，连接远程玩家'),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const DouDizhuLobbyPage(rtc: true),
                ),
              ),
            ),
          ),
        if (cardLanHostingSupported)
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('创建房间'),
              subtitle: const Text('等待玩家加入后，由主机开始对局'),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const DouDizhuLobbyPage(createRoom: true),
                ),
              ),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.login),
            title: const Text('加入房间'),
            subtitle: const Text('输入主机地址和口令'),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const DouDizhuLobbyPage()),
            ),
          ),
        ),
      ],
    ),
  );
}

class DouDizhuLobbyPage extends StatefulWidget {
  const DouDizhuLobbyPage({
    super.key,
    this.rtc = false,
    this.initialOrigin,
    this.createRoom = false,
  });
  final bool rtc;
  final bool createRoom;
  final Uri? initialOrigin;
  @override
  State<DouDizhuLobbyPage> createState() => _DouDizhuLobbyPageState();
}

class _DouDizhuLobbyPageState extends State<DouDizhuLobbyPage> {
  final _port = TextEditingController(text: '8080');
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
  String? _selectedAddress;
  bool get _host => _coordinator != null;
  @override
  void initState() {
    super.initState();
    if (widget.initialOrigin != null) {
      _address.text = widget.initialOrigin!.origin;
    }
    for (final controller in [_address, _port, _password]) {
      controller.addListener(_refresh);
    }
    if (widget.createRoom && !widget.rtc) {
      _password.text = Random.secure()
          .nextInt(10000)
          .toString()
          .padLeft(4, '0');
      unawaited(_keepScreenOn(true));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _create();
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _keepScreenOn(bool enabled) async {
    try {
      await const MethodChannel(
        'easyplay/lan',
      ).invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});
    } on MissingPluginException {
      // Android owns the window flag; other platforms need no action.
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
        _selectedAddress = addresses.isEmpty ? null : addresses.first;
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
    if (widget.initialOrigin == null) {
      final port = int.tryParse(_port.text);
      if (port == null || port < 1 || port > 65535) {
        throw StateError('请输入有效端口');
      }
      uri = uri.replace(port: port);
    }
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
    if (widget.createRoom) unawaited(_keepScreenOn(false));
    for (final c in [_address, _port, _password, _signal, _customStun]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final replica = _replica;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.rtc
              ? '斗地主 · WebRTC 房间'
              : widget.createRoom
              ? '创建斗地主房间'
              : replica != null && replica.view != null
              ? '等待开始'
              : widget.initialOrigin != null
              ? '快捷加入'
              : '加入斗地主房间',
        ),
      ),
      body: AppPageList(
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
            if (widget.createRoom)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _host ? '等待玩家加入…' : '正在创建房间…',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      if (_addresses.length > 1)
                        DropdownButton<String>(
                          value: _selectedAddress,
                          items: [
                            for (final address in _addresses)
                              DropdownMenuItem(
                                value: address,
                                child: Text(address),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedAddress = value),
                        ),
                      SelectableText(
                        _selectedAddress == null
                            ? '没有找到可分享的本机 IPv4 地址'
                            : '地址  $_selectedAddress:${_server?.port}',
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        '口令  ${_password.text}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '经典三人斗地主 · 玩家 ${replica?.seats.where((s) => s['occupied'] == true).length ?? 1}/3',
                      ),
                      const SizedBox(height: 8),
                      const Text('其他设备打开主机网页可快捷加入，也可以在 App 内输入地址和口令。'),
                      if (!_busy && !_host)
                        FilledButton(
                          onPressed: _create,
                          child: const Text('重新创建'),
                        ),
                    ],
                  ),
                ),
              )
            else if (replica?.view == null) ...[
              if (widget.initialOrigin != null)
                Text(
                  '斗地主 · ${widget.initialOrigin!.host}:${widget.initialOrigin!.port}',
                )
              else ...[
                TextField(
                  controller: _address,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '地址',
                    hintText: '192.168.1.23',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _port,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '端口'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '口令'),
              ),
              const SizedBox(height: 12),
              if (cardLanHostingSupported && widget.initialOrigin == null)
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final found = await scanLan(
                            port: int.tryParse(_port.text) ?? 8080,
                          );
                          if (!mounted) return;
                          _found = found
                              .where(
                                (r) => r.game == 'doudizhu' && r.players < 3,
                              )
                              .toList();
                          if (_found.isEmpty) {
                            _error = '没扫到可加入的房间。可手动输入主机地址和端口。';
                          }
                        }),
                  icon: const Icon(Icons.wifi_find),
                  label: Text(_busy ? '正在连接或扫描…' : '扫描斗地主房间'),
                ),
              for (final room in _found)
                ListTile(
                  leading: const Icon(Icons.wifi),
                  title: Text(room.address),
                  subtitle: Text('玩家 ${room.players}/3 · 斗地主'),
                  onTap: () {
                    _address.text = room.host;
                    _port.text = '${room.port}';
                  },
                ),
              FilledButton(
                onPressed:
                    _busy ||
                        _address.text.trim().isEmpty ||
                        _password.text.trim().isEmpty
                    ? null
                    : _join,
                child: Text(_busy ? '连接中…' : '加入'),
              ),
            ] else ...[
              const Icon(Icons.people_outline, size: 64),
              const SizedBox(height: 16),
              Text(
                replica!.connected ? '已加入斗地主房间，等待房主开始' : '与房间失去连接',
                textAlign: TextAlign.center,
              ),
              if (!replica.connected)
                OutlinedButton(
                  onPressed: _busy ? null : _join,
                  child: const Text('凭原身份重新连接'),
                ),
            ],
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
                  child: Text(widget.rtc ? '三人准备后开始' : '开始对局'),
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
