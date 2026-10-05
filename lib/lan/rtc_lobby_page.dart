import '../xiangqi/widgets/xiangqi_game_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chess/widgets/chess_game_page.dart';
import '../draughts/draughts_variant.dart';
import '../draughts/widgets/draughts_lan_pages.dart';
import '../game_session.dart';
import '../gomoku/widgets/gomoku_lan_pages.dart';
import '../gomoku/gomoku_variant.dart';
import 'lan_match_page.dart';
import 'lan_protocol.dart';
import 'rtc_manual_signaling.dart';
import 'rtc_ice_config.dart';
import 'rtc_room.dart';
import 'rtc_transport.dart';

class RtcLobbyEntry extends StatelessWidget {
  const RtcLobbyEntry({
    super.key,
    required this.game,
    this.variant,
    this.gomokuVariant = GomokuVariant.freestyle,
  });
  final String game;
  final DraughtsVariant? variant;
  final GomokuVariant gomokuVariant;
  @override
  Widget build(BuildContext context) => rtcSupported
      ? Card(
          child: ListTile(
            leading: const Icon(Icons.link),
            title: const Text('浏览器点对点联机'),
            subtitle: const Text('复制邀请和回应，与好友直接连接'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => RtcLobbyPage(
                  game: game,
                  variant: variant,
                  gomokuVariant: gomokuVariant,
                ),
              ),
            ),
          ),
        )
      : const SizedBox.shrink();
}

class RtcLobbyPage extends StatefulWidget {
  const RtcLobbyPage({
    super.key,
    required this.game,
    this.variant,
    this.gomokuVariant = GomokuVariant.freestyle,
    this.resumeRoom,
    this.iceServers,
  });
  final String game;
  final DraughtsVariant? variant;
  final GomokuVariant gomokuVariant;
  final RtcRoom? resumeRoom;
  final List<Map<String, Object?>>? iceServers;
  @override
  State<RtcLobbyPage> createState() => _RtcLobbyPageState();
}

class _RtcLobbyPageState extends State<RtcLobbyPage> {
  final _input = TextEditingController();
  final _komi = TextEditingController(text: '7.5');
  final _stun = TextEditingController(text: rtcDomesticStunUrls.join('\n'));
  String _stunPreset = 'domestic';
  bool _useStun = true;
  int _handicap = 0;
  RtcRoom? _room;
  StreamSubscription<String>? _states;
  StreamSubscription<int>? _players;
  StreamSubscription<LanMessage>? _messages;
  String? _output, _error;
  String _status = '选择创建房间，或粘贴对手的邀请';
  bool _busy = false, _connected = false, _inMatch = false;
  int _boardSize = 19;
  GoRuleSet _rules = GoRuleSet.chinese;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _room = widget.resumeRoom;
  }

  List<Map<String, Object?>> get _iceServers {
    if (widget.iceServers != null) return widget.iceServers!;
    if (!_useStun) return [];
    return switch (_stunPreset) {
      'domestic' => rtcStunServers(rtcDomesticStunUrls),
      'international' => rtcStunServers(rtcInternationalStunUrls),
      _ => parseRtcStunServers(_stun.text),
    };
  }

  Future<void> _reset() async {
    _generation++;
    await _states?.cancel();
    await _players?.cancel();
    await _messages?.cancel();
    if (widget.resumeRoom == null) {
      await _room?.close();
      _room = null;
    } else {
      await _room?.disconnectPeer();
    }
    if (!mounted) return;
    setState(() {
      _output = null;
      _error = null;
      _connected = false;
      _busy = false;
      _status = '已取消，可重新创建或加入';
    });
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = '搜集连接候选…';
    });
    final generation = ++_generation;
    try {
      if (widget.resumeRoom != null && !widget.resumeRoom!.isHost) {
        throw StateError('客人请导入房主的新邀请');
      }
      final komi = double.tryParse(_komi.text);
      if (widget.game == 'go' &&
          (komi == null || !komi.isFinite || komi < -100 || komi > 100)) {
        throw const FormatException('贴目应在 -100 到 100 之间');
      }
      final config = GoConfig(
        boardSize: _boardSize,
        rules: _rules,
        komi: komi,
        handicap: _handicap,
      )..validate();
      await _room?.disconnectPeer();
      final peer = RtcPeer(iceServers: _iceServers);
      final invitation = _room?.invitation;
      final placeholder =
          invitation ??
          RtcInvitation.offer(
            widget.game,
            'v=0',
            variant: widget.variant,
            gomokuVariant: widget.gomokuVariant,
            config: config,
          );
      final room = _room ?? RtcRoom.host(placeholder);
      _room = room;
      room.peer = peer;
      await room.prepareHost();
      _listen(peer);
      final sdp = await peer.createOffer();
      if (!mounted || generation != _generation) return;
      room.invitation = RtcInvitation(
        sessionId: placeholder.sessionId,
        token: placeholder.token,
        game: placeholder.game,
        variant: placeholder.variant,
        gomokuVariant: placeholder.gomokuVariant,
        goConfig: placeholder.goConfig,
        type: 'offer',
        sdp: sdp,
      );
      setState(() {
        _output = room.invitation.encode();
        _status = '邀请已生成，请发送给对手，再导入回应';
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _listen(RtcPeer peer) {
    _states?.cancel();
    _states = peer.states.listen((state) {
      if (mounted) setState(() => _status = state);
    });
    _players?.cancel();
    _players = _room?.coordinator?.playerCounts.listen((_) {
      if (mounted) {
        setState(() => _connected = _room!.coordinator!.playerCount == 2);
      }
      if (mounted && _connected && widget.resumeRoom != null) {
        Navigator.pop(context, true);
      }
    });
    _messages?.cancel();
    _messages = _room?.client.messages.listen((message) {
      if (message.type == LanMessageType.matchStart &&
          widget.resumeRoom == null) {
        unawaited(_enterMatch());
      }
    });
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final generation = ++_generation;
    try {
      final incoming = RtcInvitation.decode(_input.text.trim());
      if (incoming.game != widget.game ||
          incoming.variant != widget.variant ||
          (widget.game == 'gomoku' &&
              incoming.gomokuVariant != widget.gomokuVariant)) {
        throw const FormatException('邀请的棋种或规则与当前入口不一致');
      }
      if (incoming.type == 'answer') {
        if (_room == null || !_room!.isHost || _room!.peer == null) {
          throw const FormatException('请先创建邀请');
        }
        _room!.invitation.validateAnswer(incoming);
        await _room!.peer!.acceptAnswer(incoming.sdp);
      } else {
        if (_room?.isHost == true) {
          throw const FormatException('房主应导入回应，客人请重新进入加入流程');
        }
        if (widget.resumeRoom != null &&
            (incoming.sessionId != _room!.invitation.sessionId ||
                incoming.token != _room!.invitation.token)) {
          throw const FormatException('只能恢复原房间，房主刷新后无法恢复');
        }
        await _room?.disconnectPeer();
        final room = _room ?? RtcRoom.guest(incoming);
        _room = room;
        room.invitation = incoming;
        final peer = RtcPeer(iceServers: _iceServers);
        room.peer = peer;
        _listen(peer);
        final sdp = await peer.createAnswer(incoming.sdp);
        if (!mounted || generation != _generation) return;
        setState(() {
          _output = incoming.answer(sdp).encode();
          _status = '请将回应发给房主，等待连接';
        });
      }
      if (mounted && generation == _generation) {
        unawaited(_finishConnection(generation));
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _finishConnection(int generation) async {
    try {
      final room = _room!;
      final transport = await room.peer!.transport;
      if (!mounted || generation != _generation) {
        await transport.close();
        return;
      }
      await room.attachPeer(transport);
      if (widget.resumeRoom == null) {
        room.client.renegotiate = () async {
          if (!mounted) throw StateError('房主页面已关闭');
          final restored = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => RtcLobbyPage(
                game: widget.game,
                variant: widget.variant,
                gomokuVariant: widget.gomokuVariant,
                resumeRoom: room,
                iceServers: _iceServers,
              ),
            ),
          );
          if (restored != true) throw StateError('重新连接已取消');
        };
      }
      if (!mounted || generation != _generation) return;
      if (!room.isHost) {
        if (widget.resumeRoom != null) {
          Navigator.pop(context, true);
          return;
        }
        setState(() {
          _connected = true;
          _status = '已加入，等待房主开始对局';
        });
        if (room.client.started) unawaited(_enterMatch());
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$error';
          _connected = false;
        });
      }
    }
  }

  Future<void> _enterMatch() async {
    if (_inMatch || !mounted) return;
    _inMatch = true;
    final room = _room!;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => switch (widget.game) {
          'xiangqi' => XiangqiGamePage.online(connection: room.client),
          'chess' => ChessGamePage.online(connection: room.client),
          'gomoku' => GomokuLanMatchPage(connection: room.client),
          'draughts' => DraughtsLanMatchPage(
            connection: room.client,
            variant: widget.variant!,
          ),
          _ => LanMatchPage(connection: room.client),
        },
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _generation++;
    _input.dispose();
    _komi.dispose();
    _stun.dispose();
    _states?.cancel();
    _players?.cancel();
    _messages?.cancel();
    if (widget.resumeRoom == null) unawaited(_room?.close() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.resumeRoom == null ? '浏览器点对点联机' : '重新交换邀请与回应'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '与好友私下交换完整邀请和回应。信息含网络连接候选，请勿公开发布。需要双方保持页面打开；部分网络无法直连，目前未启用 TURN。',
        ),
        if (widget.game == 'gomoku')
          Text('15×15 · ${widget.gomokuVariant.label}'),
        if (widget.iceServers == null)
          ExpansionTile(
            title: const Text('连接选项'),
            children: [
              SwitchListTile(
                title: const Text('使用 STUN 帮助跨网连接'),
                subtitle: const Text('默认使用国内公共服务。仅同网连接时可关闭；关闭后不保证跨网可达。'),
                value: _useStun,
                onChanged: _busy || _room != null
                    ? null
                    : (v) => setState(() => _useStun = v),
              ),
              if (_useStun) ...[
                DropdownButtonFormField<String>(
                  initialValue: _stunPreset,
                  decoration: const InputDecoration(labelText: 'STUN 服务'),
                  items: const [
                    DropdownMenuItem(
                      value: 'domestic',
                      child: Text('国内服务（小米、芒果）'),
                    ),
                    DropdownMenuItem(
                      value: 'international',
                      child: Text('国际服务（Cloudflare、Nextcloud）'),
                    ),
                    DropdownMenuItem(value: 'custom', child: Text('自定义服务')),
                  ],
                  onChanged: _busy || _room != null
                      ? null
                      : (value) => setState(() => _stunPreset = value!),
                ),
                if (_stunPreset == 'custom')
                  TextField(
                    controller: _stun,
                    enabled: !_busy && _room == null,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'STUN 地址（每行一个，最多 4 个）',
                    ),
                  )
                else
                  Text(
                    (_stunPreset == 'domestic'
                            ? rtcDomesticStunUrls
                            : rtcInternationalStunUrls)
                        .join('\n'),
                  ),
                const Text('浏览器并行搜集多个服务的候选。公共服务可用性取决于网络；STUN 不能替代 TURN 中继。'),
              ],
            ],
          ),
        const SizedBox(height: 16),
        Text(_status),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.game == 'go' && _room == null) ...[
          DropdownButtonFormField<int>(
            initialValue: _boardSize,
            decoration: const InputDecoration(labelText: '棋盘'),
            items: [9, 13, 19]
                .map((n) => DropdownMenuItem(value: n, child: Text('$n 路')))
                .toList(),
            onChanged: _busy ? null : (n) => setState(() => _boardSize = n!),
          ),
          DropdownButtonFormField<GoRuleSet>(
            initialValue: _rules,
            decoration: const InputDecoration(labelText: '围棋规则'),
            items: GoRuleSet.values
                .map(
                  (rule) =>
                      DropdownMenuItem(value: rule, child: Text(rule.label)),
                )
                .toList(),
            onChanged: _busy ? null : (r) => setState(() => _rules = r!),
          ),
        ],
        if (widget.game == 'go' && _room == null) ...[
          TextField(
            controller: _komi,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(labelText: '贴目'),
          ),
          DropdownButtonFormField<int>(
            initialValue: _handicap,
            decoration: const InputDecoration(labelText: '让子'),
            items: [0, 2, 3, 4, 5, 6, 7, 8, 9]
                .map(
                  (n) => DropdownMenuItem(
                    value: n,
                    child: Text(n == 0 ? '无让子' : '$n 子'),
                  ),
                )
                .toList(),
            onChanged: _busy ? null : (n) => setState(() => _handicap = n!),
          ),
        ],
        const SizedBox(height: 16),
        if (_room == null || _room!.isHost)
          FilledButton.icon(
            onPressed: _busy || _output != null ? null : _create,
            icon: const Icon(Icons.add_link),
            label: const Text('创建邀请'),
          ),
        if (_output != null) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => Clipboard.setData(ClipboardData(text: _output!)),
            icon: const Icon(Icons.copy),
            label: Text(_room!.isHost ? '复制邀请信息' : '复制回应信息'),
          ),
          ExpansionTile(
            title: const Text('查看邀请 / 回应文本'),
            children: [SelectableText(_output!)],
          ),
        ],
        TextField(
          controller: _input,
          minLines: 3,
          maxLines: 6,
          maxLength: RtcInvitation.maxBytes,
          enabled: !_busy && !_connected,
          decoration: const InputDecoration(labelText: '粘贴邀请或回应信息'),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy || _connected
                  ? null
                  : () async {
                      final text = await Clipboard.getData('text/plain');
                      if (mounted) _input.text = text?.text ?? '';
                    },
              icon: const Icon(Icons.paste),
              label: const Text('粘贴'),
            ),
            FilledButton(
              onPressed: _busy || _connected ? null : _import,
              child: const Text('导入'),
            ),
            TextButton(onPressed: _reset, child: const Text('取消 / 重试')),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_room?.isHost == true && widget.resumeRoom == null) ...[
          const SizedBox(height: 16),
          Text('房间人数：${_room!.coordinator!.playerCount}/2'),
          FilledButton(
            onPressed: _connected
                ? () => _room!.coordinator!.startMatch()
                : null,
            child: const Text('开始对局'),
          ),
        ],
      ],
    ),
  );
}
