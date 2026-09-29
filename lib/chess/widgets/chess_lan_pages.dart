import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../lan/chess_lan_game.dart';
import '../../lan/lan_addresses.dart';
import '../../lan/lan_protocol.dart';
import '../../lan/lan_scanner.dart';
import '../../lan/lan_transport.dart';
import '../chess.dart' show chessRulesVersion;
import 'chess_game_page.dart';

class ChessLanLobbyPage extends StatelessWidget {
  const ChessLanLobbyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('国际象棋联机')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('标准国际象棋 · 规则版本 $chessRulesVersion'),
        const SizedBox(height: 16),
        if (lanCanHost)
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('创建房间'),
              subtitle: const Text('等待对手加入后，由主机开始对局'),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => ChessLanRoomPage()),
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
              MaterialPageRoute(builder: (_) => ChessLanJoinPage()),
            ),
          ),
        ),
      ],
    ),
  );
}

class ChessLanRoomPage extends StatefulWidget {
  const ChessLanRoomPage({super.key});

  @override
  State<ChessLanRoomPage> createState() => _ChessLanRoomPageState();
}

class _ChessLanRoomPageState extends State<ChessLanRoomPage> {
  final _token = Random.secure().nextInt(10000).toString().padLeft(4, '0');
  LanHostServer? _server;
  LanClientConnection? _hostConnection;
  StreamSubscription<int>? _players;
  List<String> _addresses = const [];
  String? _address;
  String? _error;
  bool _entering = false;

  @override
  void initState() {
    super.initState();
    _setKeepScreenOn(true);
    _start();
  }

  Future<void> _setKeepScreenOn(bool enabled) async {
    try {
      await const MethodChannel(
        'easyplay/lan',
      ).invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});
    } on MissingPluginException {
      // The window flag is only available on the Android host.
    }
  }

  Future<void> _start() async {
    final server = LanHostServer(
      chessAuthority: ChessAuthority(),
      token: _token,
    );
    try {
      await server.start();
      final addresses = await lanLocalAddresses();
      final connection = LanClientConnection.chess();
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
        _address = addresses.firstOrNull;
      });
    } catch (error) {
      await server.close();
      if (mounted) setState(() => _error = '建房失败：$error');
    }
  }

  Future<void> _startMatch() async {
    final server = _server;
    final connection = _hostConnection;
    if (server == null || connection == null || _entering) return;
    if (server.playerCount != 2) {
      setState(() => _error = '对手已离开，请等待重新加入');
      return;
    }
    setState(() {
      _error = null;
      _entering = true;
    });
    try {
      server.startMatch();
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ChessGamePage.online(connection: connection),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '无法开始对局：$error');
    } finally {
      if (mounted) setState(() => _entering = false);
    }
  }

  @override
  void dispose() {
    _setKeepScreenOn(false);
    _players?.cancel();
    _hostConnection?.close();
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('创建国际象棋房间')),
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
                  _server == null || _address == null
                      ? '没有找到可分享的本机 IPv4 地址'
                      : '地址  $_address:${_server!.port}',
                ),
                const SizedBox(height: 10),
                SelectableText(
                  '口令  $_token',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text('标准国际象棋 · 玩家 ${_server?.playerCount ?? 0}/2'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _server?.playerCount == 2 && !_entering
                      ? _startMatch
                      : null,
                  child: const Text('开始对局'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class ChessLanJoinPage extends StatefulWidget {
  const ChessLanJoinPage({super.key});

  @override
  State<ChessLanJoinPage> createState() => _ChessLanJoinPageState();
}

class _ChessLanJoinPageState extends State<ChessLanJoinPage> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8080');
  final _token = TextEditingController();
  List<LanEndpoint> _found = const [];
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
      final compatible = found
          .where((endpoint) => endpoint.game == 'chess' && endpoint.players < 2)
          .toList();
      setState(() {
        _found = compatible;
        if (compatible.isEmpty) {
          _error = '没扫到相同规则的房间。可手动输入主机地址和端口。';
        }
      });
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
    final connection = LanClientConnection.chess();
    try {
      await connection.connect(
        Uri(scheme: 'ws', host: _host.text.trim(), port: port),
        token: _token.text.trim(),
      );
      if (!mounted) {
        await connection.close();
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ChessLanWaitingPage(connection: connection),
        ),
      );
    } catch (error) {
      await connection.close();
      if (mounted) setState(() => _error = '加入失败：$error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('加入国际象棋房间')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('标准国际象棋房间'),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        if (lanCanHost)
          FilledButton.tonalIcon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(_scanning ? '正在扫描…' : '扫描同规则房间'),
          ),
        for (final endpoint in _found)
          ListTile(
            leading: const Icon(Icons.wifi),
            title: Text(endpoint.address),
            subtitle: Text('玩家 ${endpoint.players}/2 · 国际象棋'),
            onTap: () {
              _host.text = endpoint.host;
              _port.text = '${endpoint.port}';
            },
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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

class ChessLanWaitingPage extends StatefulWidget {
  const ChessLanWaitingPage({super.key, required this.connection});
  final LanClientConnection connection;

  @override
  State<ChessLanWaitingPage> createState() => _ChessLanWaitingPageState();
}

class _ChessLanWaitingPageState extends State<ChessLanWaitingPage> {
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
        builder: (_) => ChessGamePage.online(connection: widget.connection),
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
              _disconnected ? '与房间失去连接' : '已加入国际象棋房间，等待房主开始',
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
