import 'package:flutter/material.dart';

import '../../lan/rtc_transport.dart';
import '../../ui/app_layout.dart';
import '../battleship_match_controller.dart';
import 'battleship_game_page.dart';
import 'battleship_lobby_page.dart';

class BattleshipHomePage extends StatelessWidget {
  const BattleshipHomePage({super.key});

  Future<void> _local(BuildContext context, {required bool hotseat}) async {
    final controller = hotseat
        ? BattleshipMatchController.hotseat()
        : BattleshipMatchController.singlePlayer();
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => BattleshipGamePage(controller: controller),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('battleship-home'),
    appBar: AppBar(title: const Text('海战棋 Battleship')),
    body: AppPageList(
      children: [
        Text('先布阵，再侦察', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('10×10 隐藏海域，5 艘舰船。每回合开火一次，击沉敌方全部舰船获胜。'),
        const SizedBox(height: 20),
        for (final mode in [
          (
            '单人对战',
            '与设备本地 AI 对战，AI 只依据公开开火结果侦察',
            Icons.smart_toy_outlined,
            () => _local(context, hotseat: false),
          ),
          (
            '同机双人',
            '交接设备时遮挡海域，秘密布置自己的舰队',
            Icons.people_outline,
            () => _local(context, hotseat: true),
          ),
          (
            '局域网联机',
            'Android 房主，Android / Web 加入',
            Icons.wifi,
            () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const BattleshipLanLobbyPage()),
            ),
          ),
          if (rtcSupported)
            (
              'WebRTC 联机',
              '交换邀请与回应，与远程玩家对战',
              Icons.public,
              () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const BattleshipLobbyPage(rtc: true),
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
