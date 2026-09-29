import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game_session.dart' show Cell, Side, SideX;
import '../../lan/draughts_lan_game.dart';
import '../../lan/lan_addresses.dart';
import '../../lan/lan_protocol.dart';
import '../../lan/lan_scanner.dart';
import '../../lan/lan_transport.dart';
import '../draughts.dart';
import 'draughts_board.dart';

class DraughtsLanLobbyPage extends StatelessWidget {
  const DraughtsLanLobbyPage({super.key, required this.variant});

  final DraughtsVariant variant;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('跳棋联机')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${variant.label} · ${DraughtsRules.forVariant(variant).shortDescription}',
        ),
        const SizedBox(height: 16),
        if (lanCanHost)
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('创建房间'),
              subtitle: const Text('等待对手加入后，由主机开始对局'),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => DraughtsLanRoomPage(variant: variant),
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
                builder: (_) => DraughtsLanJoinPage(variant: variant),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class DraughtsLanRoomPage extends StatefulWidget {
  const DraughtsLanRoomPage({super.key, required this.variant});
  final DraughtsVariant variant;

  @override
  State<DraughtsLanRoomPage> createState() => _DraughtsLanRoomPageState();
}

class _DraughtsLanRoomPageState extends State<DraughtsLanRoomPage> {
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
      draughtsAuthority: DraughtsAuthority(widget.variant),
      token: _token,
    );
    try {
      await server.start();
      final addresses = await lanLocalAddresses();
      final connection = LanClientConnection.draughts(widget.variant);
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
          builder: (_) => DraughtsLanMatchPage(
            connection: connection,
            variant: widget.variant,
          ),
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
    appBar: AppBar(title: const Text('创建跳棋房间')),
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
                Text(
                  '${widget.variant.label} · ${DraughtsRules.forVariant(widget.variant).shortDescription} · 玩家 ${_server?.playerCount ?? 0}/2',
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

class DraughtsLanJoinPage extends StatefulWidget {
  const DraughtsLanJoinPage({super.key, required this.variant});
  final DraughtsVariant variant;

  @override
  State<DraughtsLanJoinPage> createState() => _DraughtsLanJoinPageState();
}

class _DraughtsLanJoinPageState extends State<DraughtsLanJoinPage> {
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
                endpoint.game == 'draughts' &&
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
    final connection = LanClientConnection.draughts(widget.variant);
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
          builder: (_) => DraughtsLanWaitingPage(
            connection: connection,
            variant: widget.variant,
          ),
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
    appBar: AppBar(title: const Text('加入跳棋房间')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('${widget.variant.label} 房间'),
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

class DraughtsLanWaitingPage extends StatefulWidget {
  const DraughtsLanWaitingPage({
    super.key,
    required this.connection,
    required this.variant,
  });
  final LanClientConnection connection;
  final DraughtsVariant variant;

  @override
  State<DraughtsLanWaitingPage> createState() => _DraughtsLanWaitingPageState();
}

class _DraughtsLanWaitingPageState extends State<DraughtsLanWaitingPage> {
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
        builder: (_) => DraughtsLanMatchPage(
          connection: widget.connection,
          variant: widget.variant,
        ),
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
              _disconnected
                  ? '与房间失去连接'
                  : '已加入 ${widget.variant.label} 房间，等待房主开始',
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

class DraughtsLanMatchPage extends StatefulWidget {
  const DraughtsLanMatchPage({
    super.key,
    required this.connection,
    required this.variant,
  });
  final LanClientConnection connection;
  final DraughtsVariant variant;

  @override
  State<DraughtsLanMatchPage> createState() => _DraughtsLanMatchPageState();
}

class _DraughtsLanMatchPageState extends State<DraughtsLanMatchPage> {
  StreamSubscription<LanMessage>? _messages;
  StreamSubscription<void>? _disconnects;
  Cell? _selected;
  List<Cell> _pendingPath = [];
  List<DraughtsMove> _candidates = [];
  bool _disconnected = false;
  bool _syncing = false;
  String? _message;
  int? _handledUndoSeq;
  int? _handledDrawSeq;
  late final String _recordId =
      'online-${widget.variant.name}-${DateTime.now().microsecondsSinceEpoch}';
  final DateTime _createdAt = DateTime.now().toUtc();

  DraughtsLanReplica get _replica => widget.connection.draughtsReplica!;
  DraughtsSession get _session => _replica.session;
  Side? get _side => widget.connection.side;
  bool get _myTurn =>
      widget.connection.started && !_disconnected && _side == _session.turn;

  List<Cell> get _targets {
    if (_selected == null) return const [];
    final prefix = _pendingPath.isEmpty
        ? [_selected!]
        : [_selected!, ..._pendingPath];
    return _candidates
        .where(
          (move) => move.hasPrefix(prefix) && move.path.length > prefix.length,
        )
        .map((move) => move.path[prefix.length])
        .toSet()
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _messages = widget.connection.messages.listen(_onMessage);
    _disconnects = widget.connection.disconnections.listen((_) {
      if (mounted) setState(() => _disconnected = true);
    });
  }

  void _clearSelection() {
    _selected = null;
    _pendingPath = [];
    _candidates = [];
  }

  void _onCell(Cell cell) {
    if (!_myTurn) return;
    if (_selected == null) {
      if (_session.pieceAt(cell)?.side != _side) return;
      final candidates = _session.legalMovesFrom(cell);
      if (candidates.isEmpty) return;
      setState(() {
        _selected = cell;
        _pendingPath = [];
        _candidates = candidates;
        _message = candidates.any((move) => move.isCapture)
            ? '必须吃子；请选择完整路径'
            : null;
      });
      return;
    }
    if (_selected == cell && _pendingPath.isEmpty) {
      setState(_clearSelection);
      return;
    }
    final prefix = [_selected!, ..._pendingPath, cell];
    final matches = _candidates
        .where((move) => move.hasPrefix(prefix))
        .toList();
    if (matches.isEmpty) {
      if (_session.pieceAt(cell)?.side == _side) {
        final candidates = _session.legalMovesFrom(cell);
        setState(() {
          _selected = candidates.isEmpty ? null : cell;
          _pendingPath = [];
          _candidates = candidates;
          _message = null;
        });
      }
      return;
    }
    final complete = matches
        .where((move) => move.path.length == prefix.length)
        .firstOrNull;
    if (complete != null) {
      _submitMove(complete);
      return;
    }
    setState(() {
      _pendingPath = [..._pendingPath, cell];
      _candidates = matches;
      _message = '继续选择下一跳';
    });
  }

  void _submitMove(DraughtsMove move) {
    _send(LanMessageType.move, {
      'path': move.path.map((cell) => [cell.row, cell.col]).toList(),
    });
    setState(() {
      _clearSelection();
      _message = '等待主机确认落子…';
    });
  }

  void _send(LanMessageType type, [Map<String, Object?> body = const {}]) {
    final side = _side;
    if (side == null || _disconnected) return;
    try {
      widget.connection.send(
        LanMessage(type, widget.connection.seq + 1, {
          ...body,
          'side': LanMessage.sideCode(side),
        }),
      );
    } catch (error) {
      setState(() => _message = '发送失败：$error');
    }
  }

  void _onMessage(LanMessage message) {
    if (!mounted) return;
    if (message.type == LanMessageType.rejected) {
      setState(() => _message = message.body['reason'] as String? ?? '操作未被接受');
      try {
        widget.connection.send(_replica.stateRequest());
      } catch (_) {
        // The disconnect banner handles an unavailable socket.
      }
      return;
    }
    if (message.type == LanMessageType.stateSync ||
        LanMessage.eventTypes.contains(message.type)) {
      setState(() {
        _message = null;
        _clearSelection();
      });
      _persist();
      _answerPendingRequests();
    }
  }

  void _answerPendingRequests() {
    final side = _side;
    if (side == null) return;
    final undo = _replica.undoRequest;
    if (undo != null && undo.side != side && _handledUndoSeq != undo.seq) {
      _handledUndoSeq = undo.seq;
      scheduleMicrotask(() => _answerRequest(undo, isDraw: false));
    }
    final draw = _replica.drawRequest;
    if (draw != null && draw.side != side && _handledDrawSeq != draw.seq) {
      _handledDrawSeq = draw.seq;
      scheduleMicrotask(() => _answerRequest(draw, isDraw: true));
    }
  }

  Future<void> _answerRequest(
    DraughtsNegotiation request, {
    required bool isDraw,
  }) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isDraw ? '对手请求和棋' : '对手请求悔棋'),
        content: Text(isDraw ? '是否同意结束对局？' : '是否撤回对手的最后一手？'),
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
    if (!mounted) return;
    final pending = isDraw ? _replica.drawRequest : _replica.undoRequest;
    if (pending?.seq != request.seq) return;
    _send(
      isDraw
          ? (accepted == true
                ? LanMessageType.drawAccept
                : LanMessageType.drawReject)
          : (accepted == true
                ? LanMessageType.undoAccept
                : LanMessageType.undoReject),
      {'requestSeq': request.seq},
    );
  }

  Future<void> _persist() async {
    try {
      await DraughtsStorage.save(
        DraughtsRecord.fromSession(
          _session,
          kind: DraughtsGameKind.online,
          localSide: _side,
          id: _recordId,
          createdAt: _createdAt,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _message = '自动保存失败：$error');
    }
  }

  Future<void> _reconnect() async {
    setState(() {
      _syncing = true;
      _message = null;
    });
    try {
      await widget.connection.reconnect();
      if (mounted) {
        setState(() => _disconnected = false);
        _persist();
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
    if (accepted == true) _send(LanMessageType.resign);
  }

  @override
  void dispose() {
    _messages?.cancel();
    _disconnects?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final side = _side;
    final result = session.result;
    final status = result != null
        ? result.winner == null
              ? '和棋'
              : '${result.winner!.label}获胜'
        : !_disconnected && !widget.connection.started
        ? '等待主机开始'
        : session.turn == side
        ? '轮到你 · ${side?.label ?? ''}'
        : '轮到对手 · ${session.turn.label}';
    return Scaffold(
      appBar: AppBar(title: Text('${widget.variant.label} · 联机')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Text(status, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '${session.rules.shortDescription} · ${session.moveCount} 手 · 序号 ${_replica.seq}',
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
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_message!, textAlign: TextAlign.center),
              ),
            DraughtsBoard(
              key: ValueKey(_replica.seq),
              session: session,
              selected: _selected,
              targets: _targets,
              pendingPath: _pendingPath,
              onCell: _onCell,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      !widget.connection.started ||
                          _disconnected ||
                          session.gameOver
                      ? null
                      : () => _send(LanMessageType.undoRequest),
                  icon: const Icon(Icons.undo),
                  label: const Text('请求悔棋'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      !widget.connection.started ||
                          _disconnected ||
                          session.gameOver
                      ? null
                      : () => _send(LanMessageType.drawRequest),
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('请求和棋'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      !widget.connection.started ||
                          _disconnected ||
                          session.gameOver
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
    );
  }
}
