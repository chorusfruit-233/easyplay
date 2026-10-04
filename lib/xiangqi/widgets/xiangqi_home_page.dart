import 'package:flutter/material.dart';
import 'xiangqi_ai_settings.dart';
import 'xiangqi_game_page.dart';
import 'xiangqi_lan_pages.dart';

class XiangqiHomePage extends StatelessWidget {
  const XiangqiHomePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('中国象棋')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'XIANGQI',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('标准中国象棋 · 专注这一局'),
        const SizedBox(height: 24),
        for (final item in <(String, String, IconData, Widget)>[
          (
            'AI 对战',
            '与 Pikafish 2026-09-06 对弈',
            Icons.smart_toy_outlined,
            const XiangqiAiSettingsPage(),
          ),
          ('本地双人', '在同一设备上轮流走棋', Icons.people_outline, const XiangqiGamePage()),
          ('局域网联机', '与同一网络中的朋友对弈', Icons.wifi, const XiangqiLanLobbyPage()),
        ])
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              leading: Icon(item.$3),
              title: Text(item.$1),
              subtitle: Text(item.$2),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => item.$4),
              ),
            ),
          ),
      ],
    ),
  );
}
