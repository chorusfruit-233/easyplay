import 'rtc_lobby_page.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../game_session.dart';
import 'lan_addresses.dart';
import 'lan_game.dart';
import 'lan_match_page.dart';
import 'lan_protocol.dart';
import 'lan_scanner.dart';
import 'lan_transport.dart';

class LanLobbyPage extends StatelessWidget {
  const LanLobbyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('联机对弈')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '与同一 WiFi 下的另一台设备进行围棋对局。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        RtcLobbyEntry(game: 'go'),
        if (lanCanHost)
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('创建房间'),
              subtitle: const Text('把手机变成主机，把地址和口令给对方'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const LanRoomPage()),
              ),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.login),
            title: const Text('加入房间'),
            subtitle: const Text('输入对方屏幕上的地址'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const LanJoinPage()),
            ),
          ),
        ),
      ],
    ),
  );
}

class LanRoomPage extends StatefulWidget {
  const LanRoomPage({super.key});

  @override
  State<LanRoomPage> createState() => _LanRoomPageState();
}

class _LanRoomPageState extends State<LanRoomPage> {
  final _token = Random.secure().nextInt(10000).toString().padLeft(4, '0');
  final _config = const GoConfig();
  LanHostServer? _server;
  LanClientConnection? _hostConnection;
  StreamSubscription<int>? _players;
  List<String> _addresses = const [];
  String? _address;
  String? _error;

  Future<void> _keepScreenOn(bool enabled) async {
    try {
      await const MethodChannel(
        'easyplay/lan',
      ).invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});
    } on MissingPluginException {
      // Widget tests and non-Android hosts have no native window flag.
    }
  }

  @override
  void initState() {
    super.initState();
    _keepScreenOn(true);
    _start();
  }

  Future<void> _start() async {
    final server = LanHostServer(
      authority: LanAuthority(_config),
      token: _token,
    );
    try {
      await server.start();
      final addresses = await lanLocalAddresses();
      final connection = LanClientConnection(_config);
      await connection.connect(
        Uri.parse('ws://127.0.0.1:${server.port}'),
        token: _token,
      );
      if (!mounted) {
        await connection.close();
        await server.close();
        return;
      }
      _players = server.playerCounts.listen((_) {
        if (mounted) setState(() {});
      });
      setState(() {
        _server = server;
        _hostConnection = connection;
        _addresses = addresses;
        _address = addresses.isEmpty ? null : addresses.first;
      });
    } catch (error) {
      await server.close();
      if (mounted) setState(() => _error = '建房失败：$error');
    }
  }

  @override
  void dispose() {
    _keepScreenOn(false);
    _players?.cancel();
    _hostConnection?.close();
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('创建房间')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _server == null
                      ? '正在创建房间…'
                      : _server!.playerCount >= 2
                      ? '对手已加入'
                      : '等待对手加入…',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_addresses.length > 1)
                  DropdownButton<String>(
                    value: _address,
                    items: [
                      for (final address in _addresses)
                        DropdownMenuItem(value: address, child: Text(address)),
                    ],
                    onChanged: (value) => setState(() => _address = value),
                  ),
                SelectableText(
                  _address == null || _server == null
                      ? '没有找到可分享的本机 IPv4 地址'
                      : '地址  $_address:${_server!.port}',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '口令  $_token',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  '玩家 ${_server?.playerCount ?? 0}/2 · ${_config.boardSize} 路 · ${_config.rules.label} · 贴目 ${_config.komi}',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      _server != null &&
                          _server!.playerCount >= 2 &&
                          _hostConnection != null
                      ? () async {
                          if (_server!.playerCount != 2) {
                            setState(() => _error = '对手已离开，请等待重新加入');
                            return;
                          }
                          _server!.startMatch();
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LanMatchPage(connection: _hostConnection!),
                            ),
                          );
                          if (context.mounted) Navigator.pop(context);
                        }
                      : null,
                  child: const Text('开始对局'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_server != null && _server!.playerCount < 2)
          const Text('对手加入后才能开始。'),
      ],
    ),
  );
}

class LanJoinPage extends StatefulWidget {
  const LanJoinPage({super.key});

  @override
  State<LanJoinPage> createState() => _LanJoinPageState();
}

class _LanJoinPageState extends State<LanJoinPage> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8080');
  final _token = TextEditingController();
  List<LanEndpoint> _found = const [];
  List<String> _recentAddresses = const [];
  bool _scanning = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!lanCanHost &&
        Uri.base.host.isNotEmpty &&
        Uri.base.host != 'localhost') {
      _host.text = Uri.base.host;
      _port.text = '${Uri.base.port}';
    }
    _host.addListener(_refresh);
    _token.addListener(_refresh);
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(
        () => _recentAddresses =
            prefs.getStringList('easyplay.lan.recent_addresses') ?? const [],
      );
    }
  }

  Future<void> _rememberAddress(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    final value = '$host:$port';
    final recent = [
      value,
      ..._recentAddresses.where((item) => item != value),
    ].take(5).toList();
    await prefs.setStringList('easyplay.lan.recent_addresses', recent);
    if (mounted) setState(() => _recentAddresses = recent);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final found = await scanLan(port: int.tryParse(_port.text) ?? 8080);
      if (!mounted) return;
      setState(() => _found = found);
      if (found.isEmpty) {
        setState(() => _error = '没扫到房间。可能是 AP 隔离或 VPN，请手动输入主机地址。');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '扫描失败：$error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _join() async {
    final port = int.tryParse(_port.text);
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = '请输入有效端口');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final connection = LanClientConnection(const GoConfig());
    try {
      await connection.connect(
        Uri(scheme: 'ws', host: _host.text.trim(), port: port),
        token: _token.text.trim(),
      );
      await _rememberAddress(_host.text.trim(), port);
      if (!mounted) {
        await connection.close();
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => LanGuestWaitingPage(connection: connection),
        ),
      );
    } catch (error) {
      await connection.close();
      if (mounted) {
        setState(
          () => _error = Uri.base.scheme == 'https' && !lanCanHost
              ? '加入失败：$error。若浏览器阻止了局域网连接，请打开房主地址提供的 HTTP 页面。'
              : '加入失败：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('加入房间')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _host,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '地址',
            hintText: '192.168.1.23',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '端口'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          decoration: const InputDecoration(labelText: '口令'),
        ),
        const SizedBox(height: 16),
        if (lanCanHost)
          FilledButton.tonalIcon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(_scanning ? '正在扫描…' : '扫描局域网'),
          ),
        for (final endpoint in _found)
          ListTile(
            leading: const Icon(Icons.wifi),
            title: Text(endpoint.address),
            subtitle: Text('玩家 ${endpoint.players}/2'),
            onTap: () {
              _host.text = endpoint.host;
              _port.text = '${endpoint.port}';
            },
          ),
        if (_recentAddresses.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('最近地址'),
          for (final address in _recentAddresses)
            ListTile(
              dense: true,
              title: Text(address),
              onTap: () {
                final uri = Uri.tryParse('http://$address');
                if (uri == null) return;
                _host.text = uri.host;
                _port.text = '${uri.port}';
              },
            ),
        ],
        const SizedBox(height: 12),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed:
              _connecting ||
                  _host.text.trim().isEmpty ||
                  _token.text.trim().isEmpty
              ? null
              : _join,
          child: Text(_connecting ? '连接中…' : '加入'),
        ),
      ],
    ),
  );
}

class LanGuestWaitingPage extends StatefulWidget {
  const LanGuestWaitingPage({super.key, required this.connection});

  final LanClientConnection connection;

  @override
  State<LanGuestWaitingPage> createState() => _LanGuestWaitingPageState();
}

class _LanGuestWaitingPageState extends State<LanGuestWaitingPage> {
  StreamSubscription<LanMessage>? _messages;
  StreamSubscription<void>? _disconnects;
  bool _entering = false;
  bool _disconnected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messages = widget.connection.messages.listen((message) {
      if (message.type == LanMessageType.matchStart) _enterMatch();
    });
    _disconnects = widget.connection.disconnections.listen((_) {
      if (mounted) setState(() => _disconnected = true);
    });
    if (widget.connection.started) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _enterMatch());
    }
  }

  Future<void> _enterMatch() async {
    if (!mounted || _entering) return;
    setState(() => _entering = true);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LanMatchPage(connection: widget.connection),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reconnect() async {
    setState(() => _error = null);
    try {
      await widget.connection.reconnect();
      if (!mounted) return;
      setState(() => _disconnected = false);
      if (widget.connection.started) _enterMatch();
    } catch (error) {
      if (mounted) setState(() => _error = '重连失败：$error');
    }
  }

  @override
  void dispose() {
    _messages?.cancel();
    _disconnects?.cancel();
    widget.connection.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('等待开始')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 64),
            const SizedBox(height: 20),
            Text(
              _disconnected ? '与房间失去连接' : '已加入房间，等待房主开始对局',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
            ],
            if (_disconnected) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: _reconnect, child: const Text('重新连接')),
            ],
          ],
        ),
      ),
    ),
  );
}
