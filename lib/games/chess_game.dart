import 'package:flutter/material.dart';

/// Chess remains unavailable until its rules and gameplay are complete.
class ChessGamePage extends StatelessWidget {
  const ChessGamePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _GameUnavailablePage(title: '国际象棋', message: '国际象棋功能尚未完成。');
}

class _GameUnavailablePage extends StatelessWidget {
  final String title;
  final String message;

  const _GameUnavailablePage({required this.title, required this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(child: Text(message)),
  );
}
