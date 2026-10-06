import '../../ui/app_layout.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game_session.dart' show Cell, Side, SideX;
import '../../go_placement.dart';
import '../../lan/gomoku_lan_game.dart';
import '../../lan/lan_addresses.dart';
import '../../lan/lan_protocol.dart';
import '../../lan/lan_rematch_card.dart';
import '../../lan/lan_scanner.dart';
import '../../lan/lan_transport.dart';
import '../../lan/rtc_lobby_page.dart';
import '../gomoku_session.dart';
import 'gomoku_board.dart';

class GomokuLanLobbyPage extends StatelessWidget {
  const GomokuLanLobbyPage({super.key, this.variant = GomokuVariant.freestyle});
  final GomokuVariant variant;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('五子棋联机')),
    body: AppPageList(
      children: [
        Text('15×15 · ${variant.label}'),
        Text(variant.description),
        const SizedBox(height: 16),
        RtcLobbyEntry(game: 'gomoku', gomokuVariant: variant),
        if (lanCanHost)
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('创建房间'),
              subtitle: const Text('等待对手加入后，由主机开始对局'),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => GomokuLanRoomPage(variant: variant),
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
              MaterialPageRoute(
                builder: (_) => GomokuLanJoinPage(variant: variant),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class GomokuLanRoomPage extends StatefulWidget {
  const GomokuLanRoomPage({super.key, this.variant = GomokuVariant.freestyle});
  final GomokuVariant variant;

  @override
  State<GomokuLanRoomPage> createState() => _GomokuLanRoomPageState();
}

class _GomokuLanRoomPageState extends State<GomokuLanRoomPage> {
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
      gomokuAuthority: GomokuLanAuthority(variant: widget.variant),
      token: _token,
    );
    try {
      await server.start();
      final addresses = await lanLocalAddresses();
      final connection = LanClientConnection.gomoku(variant: widget.variant);
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
          builder: (_) => GomokuLanMatchPage(connection: connection),
        ),
      );
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
    appBar: AppBar(title: const Text('创建五子棋房间')),
    body: AppPageList(
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
                Text(
                  '15×15 · ${widget.variant.label} · 玩家 ${_server?.playerCount ?? 0}/2',
                ),
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

class GomokuLanJoinPage extends StatefulWidget {
  const GomokuLanJoinPage({super.key, this.variant = GomokuVariant.freestyle});
  final GomokuVariant variant;

  @override
  State<GomokuLanJoinPage> createState() => _GomokuLanJoinPageState();
}

class _GomokuLanJoinPageState extends State<GomokuLanJoinPage> {
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
          .where(
            (endpoint) =>
                endpoint.game == 'gomoku' &&
                endpoint.variant == widget.variant.name &&
                endpoint.players < 2,
          )
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
    final connection = LanClientConnection.gomoku(variant: widget.variant);
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
          builder: (_) => GomokuLanWaitingPage(connection: connection),
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
    appBar: AppBar(title: const Text('加入五子棋房间')),
    body: AppPageList(
      children: [
        Text('15×15 · ${widget.variant.label}房间'),
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
            subtitle: Text(
              '玩家 ${endpoint.players}/2 · ${widget.variant.label}',
            ),
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

class GomokuLanWaitingPage extends StatefulWidget {
  const GomokuLanWaitingPage({super.key, required this.connection});
  final LanClientConnection connection;

  @override
  State<GomokuLanWaitingPage> createState() => _GomokuLanWaitingPageState();
}

class _GomokuLanWaitingPageState extends State<GomokuLanWaitingPage> {
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
        builder: (_) => GomokuLanMatchPage(connection: widget.connection),
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
            Text('15×15 · ${widget.connection.gomokuVariant!.label}'),
            Text(
              _disconnected ? '与房间失去连接' : '已加入五子棋房间，等待房主开始',
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

class GomokuLanMatchPage extends StatefulWidget {
  const GomokuLanMatchPage({super.key, required this.connection});
  final LanClientConnection connection;

  @override
  State<GomokuLanMatchPage> createState() => _GomokuLanMatchPageState();
}

class _GomokuLanMatchPageState extends State<GomokuLanMatchPage>
    with WidgetsBindingObserver {
  StreamSubscription<LanMessage>? _messages;
  StreamSubscription<void>? _disconnects;
  bool _disconnected = false;
  bool _syncing = false;
  bool _pending = false;
  String? _message;
  int? _handledUndoSeq;
  GoPlacementMode _placementMode = GoPlacementMode.automatic;

  GomokuLanReplica get _replica => widget.connection.gomokuReplica!;
  GomokuSession get _session => _replica.session;
  Side? get _side => widget.connection.side;
  bool get _connected =>
      widget.connection.started && !_disconnected && !_syncing && !_pending;
  bool get _negotiating =>
      _replica.undoRequest != null || _replica.rematchRequest != null;
  bool get _myTurn =>
      _connected &&
      !_negotiating &&
      !_session.gameOver &&
      _side == _session.turn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages = widget.connection.messages.listen(_onMessage);
    _disconnects = widget.connection.disconnections.listen((_) {
      if (mounted) setState(() => _disconnected = true);
    });
    _loadPlacement();
    WidgetsBinding.instance.addPostFrameCallback((_) => _answerPendingUndo());
  }

  Future<void> _loadPlacement() async {
    final mode = await GoPlacementPreferences.load();
    if (mounted) setState(() => _placementMode = mode);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPlacement();
  }

  void _onCell(Cell cell) {
    if (!_myTurn) return;
    final reason = _session.rejectionReason(cell);
    if (reason != null) {
      setState(() => _message = reason);
      return;
    }
    _send(LanMessageType.move, {
      'cell': [cell.row, cell.col],
    });
  }

  void _send(LanMessageType type, [Map<String, Object?> body = const {}]) {
    final side = _side;
    if (side == null || !_connected) return;
    try {
      widget.connection.send(
        LanMessage(type, widget.connection.seq + 1, {
          ...body,
          'side': LanMessage.sideCode(side),
        }),
      );
      setState(() {
        _pending = true;
        _message = null;
      });
    } catch (error) {
      setState(() => _message = '发送失败：$error');
    }
  }

  void _onMessage(LanMessage message) {
    if (!mounted) return;
    if (message.type == LanMessageType.rejected) {
      setState(() {
        _pending = false;
        _syncing = true;
        _message = message.body['reason'] as String? ?? '操作未被接受';
      });
      try {
        widget.connection.send(_replica.stateRequest());
      } catch (_) {
        setState(() {
          _syncing = false;
          _disconnected = true;
        });
      }
      return;
    }
    if (message.type == LanMessageType.stateSync ||
        LanMessage.eventTypes.contains(message.type)) {
      setState(() {
        _pending = false;
        _syncing = false;
        if (message.type != LanMessageType.stateSync) _message = null;
      });
      _answerPendingUndo();
    }
  }

  void _answerPendingUndo() {
    if (!mounted) return;
    final undo = _replica.undoRequest;
    if (undo != null && undo.side != _side && _handledUndoSeq != undo.seq) {
      _handledUndoSeq = undo.seq;
      scheduleMicrotask(() => _answerUndo(undo));
    }
  }

  Future<void> _answerUndo(GomokuNegotiation request) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('对手请求悔棋'),
        content: const Text('是否撤回对手刚下的一子？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意'),
          ),
        ],
      ),
    );
    if (!mounted || _replica.undoRequest?.seq != request.seq) return;
    _send(
      accepted == true ? LanMessageType.undoAccept : LanMessageType.undoReject,
      {'requestSeq': request.seq, if (accepted != true) 'reason': '对方拒绝悔棋'},
    );
  }

  Future<void> _reconnect() async {
    setState(() {
      _syncing = true;
      _message = null;
    });
    try {
      await widget.connection.reconnect();
      if (mounted) {
        setState(() {
          _disconnected = false;
          _pending = false;
        });
        _answerPendingUndo();
      }
    } catch (error) {
      if (mounted) setState(() => _message = '重连失败：$error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _resign() async {
    final side = _side;
    if (side == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('认输'),
        content: Text('${side.label}确认认输吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('认输'),
          ),
        ],
      ),
    );
    if (mounted && accepted == true && !_negotiating && !_session.gameOver) {
      _send(LanMessageType.resign);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messages?.cancel();
    _disconnects?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final side = _side;
    final status = session.gameOver
        ? session.turnLabel
        : !widget.connection.started
        ? '等待主机开始'
        : session.turn == side
        ? '轮到你 · ${side?.label ?? ''}'
        : '轮到对手 · ${session.turn.label}';
    return Scaffold(
      appBar: AppBar(title: const Text('五子棋 · 联机')),
      body: SafeArea(
        child: GomokuMatchLayout(
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Text(
                        status,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '15×15 · ${session.variant.label} · ${session.moves.length} 手',
                      ),
                    ],
                  ),
                ),
              ),
              if (_disconnected)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    title: const Text('与房间失去连接'),
                    trailing: FilledButton(
                      onPressed: _syncing ? null : _reconnect,
                      child: Text(_syncing ? '重连中…' : '重新连接'),
                    ),
                  ),
                ),
              if (_message != null)
                Text(_message!, textAlign: TextAlign.center),
            ],
          ),
          board: GomokuBoard(
            key: ValueKey(_replica.seq),
            session: session,
            enabled: _myTurn,
            placementMode: _placementMode,
            onCell: _onCell,
          ),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (session.gameOver && side != null)
                LanRematchCard(
                  request: _replica.rematchRequest,
                  side: side,
                  enabled: _connected,
                  onSend: _send,
                ),
              if (_negotiating && !session.gameOver)
                const Text('等待处理悔棋请求…', textAlign: TextAlign.center),
              if (_pending) const Text('等待主机确认…', textAlign: TextAlign.center),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        !_connected ||
                            _negotiating ||
                            side == null ||
                            !_replica.canRequestUndo(side)
                        ? null
                        : () => _send(LanMessageType.undoRequest),
                    icon: const Icon(Icons.undo),
                    label: const Text('请求悔棋'),
                  ),
                  OutlinedButton.icon(
                    onPressed: !_connected || _negotiating || session.gameOver
                        ? null
                        : _resign,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('认输'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
