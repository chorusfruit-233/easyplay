import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../lan/lan_addresses.dart';
import '../../lan/lan_scanner.dart';
import '../../lan/message_transport.dart';
import '../../lan/rtc_ice_config.dart';
import '../../lan/rtc_transport.dart';
import '../../ui/app_layout.dart';
import '../battleship.dart';
import '../battleship_match_controller.dart';
import '../multiplayer/battleship_lan.dart';
import '../multiplayer/battleship_replica.dart';
import '../multiplayer/battleship_room_coordinator.dart';
import '../multiplayer/battleship_rtc_room.dart';
import 'battleship_game_page.dart';

class BattleshipLanLobbyPage extends StatelessWidget {
  const BattleshipLanLobbyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('海战棋联机')),
    body: AppPageList(
      children: [
        const Text('经典双人海战棋 · 各自布阵，轮流开火'),
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
                  builder: (_) => const BattleshipLobbyPage(rtc: true),
                ),
              ),
            ),
          ),
        if (battleshipLanHostingSupported)
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('创建房间'),
              subtitle: const Text('分享地址和口令，等待另一位玩家加入'),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const BattleshipLobbyPage(createRoom: true),
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
              MaterialPageRoute(builder: (_) => const BattleshipLobbyPage()),
            ),
          ),
        ),
      ],
    ),
  );
}

class BattleshipLobbyPage extends StatefulWidget {
  const BattleshipLobbyPage({
    super.key,
    this.rtc = false,
    this.createRoom = false,
    this.initialOrigin,
  });

  final bool rtc;
  final bool createRoom;
  final Uri? initialOrigin;

  @override
  State<BattleshipLobbyPage> createState() => _BattleshipLobbyPageState();
}

class _BattleshipLobbyPageState extends State<BattleshipLobbyPage> {
  final _address = TextEditingController();
  final _port = TextEditingController(text: '8080');
  final _password = TextEditingController();
  final _signal = TextEditingController();
  final _customStun = TextEditingController();
  BattleshipRoomCoordinator? _coordinator;
  BattleshipLanServer? _server;
  BattleshipRtcRoom? _rtcRoom;
  BattleshipReplica? _replica;
  List<LanEndpoint> _found = [];
  List<String> _addresses = [];
  String? _selectedAddress;
  String? _error;
  String? _outgoing;
  String _stun = 'domestic';
  bool _busy = false;
  bool _closing = false;
  bool _gameOpened = false;
  bool _openingGame = false;

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
    if (mounted && !_closing) setState(() {});
  }

  Future<void> _keepScreenOn(bool enabled) async {
    try {
      await const MethodChannel(
        'easyplay/lan',
      ).invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});
    } on MissingPluginException {
      // Only the Android host owns a window flag.
    }
  }

  List<Map<String, Object?>> get _ice => switch (_stun) {
    'none' => [],
    'international' => rtcStunServers(rtcInternationalStunUrls),
    'custom' => parseRtcStunServers(_customStun.text),
    _ => rtcStunServers(rtcDomesticStunUrls),
  };

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || !mounted || _closing) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted && !_closing) {
        setState(() {
          _error = switch (error) {
            StateError() => error.message.toString(),
            FormatException() => error.message,
            _ => '$error',
          };
        });
      }
    } finally {
      if (mounted && !_closing) setState(() => _busy = false);
    }
  }

  void _observe(BattleshipReplica replica) {
    _replica?.removeListener(_changed);
    _replica = replica;
    replica.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (!mounted || _closing) return;
    setState(() {});
    if (!_gameOpened && _replica?.started == true) {
      _gameOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openGame());
    }
  }

  Future<void> _openGame() async {
    if (!mounted || _closing || _replica == null || _openingGame) return;
    _openingGame = true;
    final controller = BattleshipMatchController.network(_replica!);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => BattleshipGamePage(controller: controller),
        ),
      );
    } finally {
      controller.dispose();
      _openingGame = false;
    }
    // Keeping the lobby alive allows manual WebRTC renegotiation after a loss.
    if (mounted && !_closing) setState(() {});
  }

  Future<void> _create() => _run(() async {
    if (widget.rtc) {
      final room = BattleshipRtcRoom.host(iceServers: _ice);
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
      return;
    }
    final password = _password.text.trim();
    if (password.isEmpty) throw StateError('请先设置房间口令');
    final coordinator = BattleshipRoomCoordinator(password: password);
    final server = BattleshipLanServer(coordinator);
    final replica = BattleshipReplica();
    try {
      await server.start();
      final addresses = await lanLocalAddresses();
      final (host, client) = MemoryTransport.pair();
      coordinator.attach(host, fixedSeat: BattleshipSeat.player1);
      await replica.bind(client, token: coordinator.hostCredential);
      if (!mounted || _closing) {
        await replica.close();
        await coordinator.close();
        await server.close();
        return;
      }
      _coordinator = coordinator;
      _server = server;
      _addresses = addresses;
      _selectedAddress = addresses.firstOrNull;
      _observe(replica);
    } catch (_) {
      await replica.close();
      await coordinator.close();
      await server.close();
      rethrow;
    }
  });

  Uri _connectionUri() {
    var raw = _address.text.trim();
    if (!raw.contains('://')) raw = 'ws://$raw';
    var uri = Uri.tryParse(raw);
    if (uri == null) throw StateError('请输入有效主机地址');
    if (widget.initialOrigin == null) {
      final port = int.tryParse(_port.text.trim());
      if (port == null || port < 1 || port > 65535) {
        throw StateError('请输入有效端口');
      }
      uri = uri.replace(port: port);
    }
    if (uri.scheme == 'http') uri = uri.replace(scheme: 'ws');
    if (uri.scheme == 'https') uri = uri.replace(scheme: 'wss');
    if (!['ws', 'wss'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw StateError('地址格式为 192.168.1.10，端口单独填写');
    }
    return uri;
  }

  Future<void> _join() => _run(() async {
    final password = _password.text.trim();
    if (password.isEmpty) throw StateError('请输入房间口令');
    final uri = _connectionUri();
    final replica = _replica ?? BattleshipReplica();
    Future<void> connect() async {
      final transport = await connectBattleshipSocket(uri);
      if (!mounted || _closing) {
        await transport.close();
        return;
      }
      await replica.bind(transport, token: password);
    }

    replica.reconnect = connect;
    _observe(replica);
    await connect();
    if (mounted && !_closing) _observe(replica);
  });

  Future<void> _offer() => _run(() async {
    if (_rtcRoom == null || !_host) throw StateError('请先创建房间');
    _outgoing = null;
    _signal.clear();
    _outgoing = await _rtcRoom!.offer();
  });

  Future<void> _answer() => _run(() async {
    _outgoing = null;
    _rtcRoom ??= BattleshipRtcRoom.guest(iceServers: _ice);
    _observe(_rtcRoom!.replica);
    _outgoing = await _rtcRoom!.answer(_signal.text.trim());
  });

  Future<void> _accept() => _run(() async {
    if (_rtcRoom == null || !_host) throw StateError('请先创建房间');
    await _rtcRoom!.accept(_signal.text.trim());
  });

  Future<void> _scan() => _run(() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      throw StateError('请输入有效端口');
    }
    final found = await scanLan(port: port);
    if (!mounted || _closing) return;
    _found = found
        .where((room) => room.game == 'battleship' && room.players < 2)
        .toList();
    if (_found.isEmpty) _error = '没扫到可加入的海战棋房间，可手动填写地址和端口。';
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
    for (final controller in [
      _address,
      _port,
      _password,
      _signal,
      _customStun,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _rtcControls(BattleshipReplica? replica) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('将邀请发给另一位玩家，再粘贴对方的回应。断线后使用原座位重新交换邀请。'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _stun,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '连接选项'),
        items: const [
          DropdownMenuItem(value: 'domestic', child: Text('国内 STUN')),
          DropdownMenuItem(value: 'international', child: Text('国际 STUN')),
          DropdownMenuItem(value: 'none', child: Text('同网连接（关闭 STUN）')),
          DropdownMenuItem(value: 'custom', child: Text('自定义 STUN')),
        ],
        onChanged: replica == null
            ? (value) => setState(() => _stun = value!)
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
          child: const Text('创建双人房间'),
        ),
      if (_host)
        OutlinedButton(
          onPressed: _busy ? null : _offer,
          child: const Text('生成邀请 / 重连邀请'),
        ),
      TextField(
        controller: _signal,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: _host ? '粘贴对方的回应' : '粘贴房主邀请（重连须为原座位）',
        ),
      ),
      const SizedBox(height: 8),
      FilledButton.tonal(
        onPressed: _busy ? null : (_host ? _accept : _answer),
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
          label: Text(_host ? '复制邀请，发给对方' : '复制回应，发给房主'),
        ),
      ],
      const SizedBox(height: 8),
      const Text('无 TURN 时部分网络无法直连，可切换连接选项或使用局域网。'),
    ],
  );

  Widget _hostCard(BattleshipReplica? replica) => Card(
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
              isExpanded: true,
              items: [
                for (final address in _addresses)
                  DropdownMenuItem(value: address, child: Text(address)),
              ],
              onChanged: (value) => setState(() => _selectedAddress = value),
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
            '经典双人海战棋 · 玩家 ${replica?.seats.where((seat) => seat['occupied'] == true).length ?? 1}/2',
          ),
          const SizedBox(height: 8),
          const Text('另一台设备可打开主机网页快捷加入，或在 App 内填写地址和口令。双方连接后由房主开始布阵。'),
          if (!_busy && !_host)
            FilledButton(onPressed: _create, child: const Text('重新创建')),
        ],
      ),
    ),
  );

  List<Widget> _joinControls(BattleshipReplica? replica) {
    if (replica?.view != null) {
      return [
        const Icon(Icons.people_outline, size: 64),
        const SizedBox(height: 16),
        Text(
          replica!.connected ? '已加入海战棋房间，等待房主开始' : '与房间失去连接',
          textAlign: TextAlign.center,
        ),
        if (!replica.connected)
          OutlinedButton(
            onPressed: _busy ? null : _join,
            child: const Text('凭原身份重新连接'),
          ),
      ];
    }
    return [
      if (widget.initialOrigin != null)
        Text(
          '海战棋 · ${widget.initialOrigin!.host}:${widget.initialOrigin!.port}',
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
      if (battleshipLanHostingSupported && widget.initialOrigin == null)
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _scan,
          icon: const Icon(Icons.wifi_find),
          label: Text(_busy ? '正在连接或扫描…' : '扫描海战棋房间'),
        ),
      for (final room in _found)
        ListTile(
          leading: const Icon(Icons.wifi),
          title: Text(room.address),
          subtitle: Text('玩家 ${room.players}/2 · 海战棋'),
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    final replica = _replica;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.rtc
              ? '海战棋 · WebRTC 房间'
              : widget.createRoom
              ? '创建海战棋房间'
              : replica?.view != null
              ? '等待开始'
              : widget.initialOrigin != null
              ? '快捷加入'
              : '加入海战棋房间',
        ),
      ),
      body: AppPageList(
        children: [
          const Text('双人海战棋。舰队布置仅对自己可见；房主退出后房间关闭，对局不保存。'),
          const SizedBox(height: 16),
          if (widget.rtc)
            _rtcControls(replica)
          else if (widget.createRoom)
            _hostCard(replica)
          else
            ..._joinControls(replica),
          const SizedBox(height: 20),
          if (replica != null) ...[
            for (var index = 0; index < replica.seats.length; index++)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(BattleshipSeat.values[index].label),
                subtitle: Text(
                  replica.seats[index]['connected'] == true
                      ? '已连接'
                      : replica.seats[index]['occupied'] == true
                      ? '离线 · 保留座位，等待重连'
                      : '空座位',
                ),
              ),
            if (!replica.started && _host)
              FilledButton(
                onPressed: !_busy && _coordinator!.canStart
                    ? () => replica.send('start')
                    : null,
                child: const Text('开始对局'),
              ),
            if (replica.started)
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
