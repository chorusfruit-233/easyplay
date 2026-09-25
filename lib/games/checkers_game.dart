import 'package:flutter/material.dart';

/// Checkers remains unavailable until its rules and gameplay are complete.
class CheckersGamePage extends StatelessWidget {
  const CheckersGamePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('跳棋')),
    body: const Center(child: Text('跳棋功能尚未完成。')),
  );
}
