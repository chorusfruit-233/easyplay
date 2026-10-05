import 'package:flutter/material.dart';
import '../../lan/message_transport.dart';
import '../../lan/rtc_transport.dart';
import '../doudizhu_model.dart';
import '../doudizhu_match_controller.dart';
import '../multiplayer/card_room_coordinator.dart';
import '../multiplayer/doudizhu_replica.dart';
import 'doudizhu_game_page.dart';
import 'doudizhu_lobby_page.dart';

class DouDizhuHomePage extends StatelessWidget {
  const DouDizhuHomePage({super.key});
  Future<void> _single(BuildContext context) async {
    final room = CardRoomCoordinator(password: cardSecret());
    final replica = DouDizhuReplica();
    room.setAi(PlayerSeat.seat1, true);
    room.setAi(PlayerSeat.seat2, true);
    final (server, client) = MemoryTransport.pair();
    room.attach(server, fixedSeat: PlayerSeat.seat0);
    DouDizhuMatchController? controller;
    try {
      await replica.bind(client, token: room.hostCredential);
      replica.send('ready');
      await replica.waitForSnapshot((r) => room.canStart && r.seq == room.seq);
      replica.send('start');
      await replica.waitForSnapshot(
        (r) => r.view?.publicState.phase != DouDizhuPhase.waiting,
      );
      if (!context.mounted) return;
      controller = DouDizhuMatchController.network(replica);
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DouDizhuGamePage(controller: controller!),
        ),
      );
    } finally {
      controller?.dispose();
      await replica.close();
      await room.close();
    }
  }

  Future<void> _hotseat(BuildContext context) async {
    final controller = DouDizhuMatchController.hotseat();
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DouDizhuGamePage(controller: controller),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('斗地主')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('经典三人斗地主', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('一副 54 张牌，叫分选地主，农民共同获胜。无下注或积分结算。'),
        const SizedBox(height: 20),
        for (final mode in [
          (
            '单人对战',
            '你与两名本地 AI',
            Icons.smart_toy_outlined,
            () => _single(context),
          ),
          ('同机三人', '交接设备时遮挡手牌', Icons.groups_outlined, () => _hotseat(context)),
          (
            '局域网联机',
            'Android 房主，Android / Web 加入',
            Icons.wifi,
            () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const DouDizhuLobbyPage()),
            ),
          ),
          if (rtcSupported)
            (
              'WebRTC 联机',
              '手动交换邀请，三名真人或 AI 补位',
              Icons.public,
              () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const DouDizhuLobbyPage(rtc: true),
                ),
              ),
            ),
        ])
          Card(
            child: ListTile(
              leading: Icon(mode.$3),
              title: Text(mode.$1),
              subtitle: Text(mode.$2),
              trailing: const Icon(Icons.chevron_right),
              onTap: mode.$4,
            ),
          ),
      ],
    ),
  );
}
