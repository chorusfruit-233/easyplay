import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps the board visible while status, controls and records can scroll.
class DraughtsMatchLayout extends StatelessWidget {
  const DraughtsMatchLayout({
    super.key,
    required this.header,
    required this.board,
    required this.footer,
  });

  final Widget header;
  final Widget board;
  final Widget footer;

  Widget _fittedBoard() => LayoutBuilder(
    builder: (context, constraints) => Center(
      child: SizedBox.square(
        dimension: math.min(constraints.maxWidth, constraints.maxHeight),
        child: board,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _fittedBoard()),
              const SizedBox(width: 16),
              SizedBox(
                width: 310,
                child: SingleChildScrollView(
                  child: Column(children: [header, footer]),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .3,
              ),
              child: SingleChildScrollView(child: header),
            ),
            Expanded(child: _fittedBoard()),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .25,
              ),
              child: SingleChildScrollView(child: footer),
            ),
          ],
        );
      },
    ),
  );
}
