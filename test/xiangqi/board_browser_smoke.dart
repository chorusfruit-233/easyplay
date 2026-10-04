// Standalone visual target for bundled piece glyphs; not shipped as app routing.
import 'package:flutter/material.dart';
import 'package:easyplay/xiangqi/widgets/xiangqi_game_page.dart';

void main() => runApp(
  MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: const XiangqiGamePage(),
  ),
);
