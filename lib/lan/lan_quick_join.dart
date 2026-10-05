import '../doudizhu/widgets/doudizhu_lobby_page.dart';
import '../xiangqi/widgets/xiangqi_lan_pages.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../chess/widgets/chess_lan_pages.dart';
import '../draughts/draughts_variant.dart';
import '../draughts/widgets/draughts_lan_pages.dart';
import '../game_session.dart';
import '../gomoku/widgets/gomoku_lan_pages.dart';
import '../gomoku/gomoku_variant.dart';
import 'lan_page.dart';
import 'lan_protocol.dart';
import 'lan_transport.dart';

class LanWebRoom {
  const LanWebRoom(
    this.origin,
    this.game,
    this.variant, {
    this.gomokuVariant = GomokuVariant.freestyle,
  });
  final Uri origin;
  final String game;
  final DraughtsVariant? variant;
  final GomokuVariant gomokuVariant;

  String get label => switch (game) {
    'chess' => '国际象棋',
    'doudizhu' => '斗地主',
    'xiangqi' => '中国象棋',
    'gomoku' => '五子棋 · ${gomokuVariant.label}',
    'draughts' => '跳棋 · ${variant!.label}',
    _ => '围棋',
  };

  static Future<LanWebRoom?> probe(Uri origin, {http.Client? client}) async {
    if (!['http', 'https'].contains(origin.scheme) || origin.host.isEmpty) {
      return null;
    }
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .get(origin.resolve('/easyplay/probe'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map ||
          data['app'] != 'easyplay' ||
          data['version'] != lanProtocolVersion) {
        return null;
      }
      final game = data['game'];
      if (![
        'go',
        'chess',
        'draughts',
        'gomoku',
        'xiangqi',
        'doudizhu',
      ].contains(game)) {
        return null;
      }
      if (game == 'doudizhu' &&
          (data['rulesVersion'] != 1 ||
              data['protocolVersion'] != 1 ||
              data['maxPlayers'] != 3)) {
        return null;
      }
      if (game == 'xiangqi') {
        LanMessage.validateXiangqiConfig(Map<String, Object?>.from(data));
      }
      final gomokuVariant = game == 'gomoku'
          ? LanMessage.parseGomokuVariant(Map<String, Object?>.from(data))
          : GomokuVariant.freestyle;
      DraughtsVariant? variant;
      if (game == 'draughts') {
        for (final item in DraughtsVariant.values) {
          if (item.name == data['variant']) variant = item;
        }
        if (variant == null) return null;
      }
      return LanWebRoom(
        origin,
        game as String,
        variant,
        gomokuVariant: gomokuVariant,
      );
    } catch (_) {
      // Ordinary Web deployments do not have a LAN host endpoint.
      return null;
    } finally {
      if (client == null) transport.close();
    }
  }
}

class LanQuickJoinCard extends StatefulWidget {
  const LanQuickJoinCard({super.key, this.loadRoom});
  final Future<LanWebRoom?> Function()? loadRoom;

  @override
  State<LanQuickJoinCard> createState() => _LanQuickJoinCardState();
}

class _LanQuickJoinCardState extends State<LanQuickJoinCard> {
  late final Future<LanWebRoom?> _room = widget.loadRoom != null
      ? widget.loadRoom!()
      : kIsWeb
      ? LanWebRoom.probe(Uri.base)
      : Future.value(null);

  @override
  Widget build(BuildContext context) => FutureBuilder<LanWebRoom?>(
    future: _room,
    builder: (context, snapshot) {
      final room = snapshot.data;
      if (room == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.wifi),
            title: const Text('加入当前主机房间'),
            subtitle: Text('${room.label} · 输入口令即可加入'),
            trailing: FilledButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => room.game == 'doudizhu'
                      ? DouDizhuLobbyPage(initialOrigin: room.origin)
                      : LanQuickJoinPage(room: room),
                ),
              ),
              child: const Text('快捷加入'),
            ),
          ),
        ),
      );
    },
  );
}

class LanQuickJoinPage extends StatefulWidget {
  const LanQuickJoinPage({super.key, required this.room});
  final LanWebRoom room;

  @override
  State<LanQuickJoinPage> createState() => _LanQuickJoinPageState();
}

class _LanQuickJoinPageState extends State<LanQuickJoinPage> {
  final _token = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_connecting || _token.text.trim().isEmpty) return;
    final room = widget.room;
    final connection = switch (room.game) {
      'chess' => LanClientConnection.chess(),
      'xiangqi' => LanClientConnection.xiangqi(),
      'gomoku' => LanClientConnection.gomoku(variant: room.gomokuVariant),
      'draughts' => LanClientConnection.draughts(room.variant!),
      _ => LanClientConnection(const GoConfig()),
    };
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await connection.connect(
        Uri(
          scheme: room.origin.scheme == 'https' ? 'wss' : 'ws',
          host: room.origin.host,
          port: room.origin.port,
        ),
        token: _token.text.trim(),
      );
      if (!mounted) {
        await connection.close();
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => switch (room.game) {
            'xiangqi' => XiangqiLanWaitingPage(connection: connection),
            'chess' => ChessLanWaitingPage(connection: connection),
            'gomoku' => GomokuLanWaitingPage(connection: connection),
            'draughts' => DraughtsLanWaitingPage(
              connection: connection,
              variant: room.variant!,
            ),
            _ => LanGuestWaitingPage(connection: connection),
          },
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
  Widget build(BuildContext context) => widget.room.game == 'doudizhu'
      ? DouDizhuLobbyPage(initialOrigin: widget.room.origin)
      : Scaffold(
          appBar: AppBar(title: const Text('快捷加入')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${widget.room.label} · ${widget.room.origin.host}:${widget.room.origin.port}',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _token,
                autofocus: true,
                enabled: !_connecting,
                decoration: const InputDecoration(labelText: '房间口令'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _join(),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: _connecting || _token.text.trim().isEmpty
                    ? null
                    : _join,
                child: Text(_connecting ? '连接中…' : '加入'),
              ),
            ],
          ),
        );
}
