import 'package:flutter/material.dart';

import '../game_session.dart' show Side;
import 'lan_protocol.dart';
import 'lan_rematch.dart';

class LanRematchCard extends StatelessWidget {
  const LanRematchCard({
    super.key,
    required this.request,
    required this.side,
    required this.enabled,
    required this.onSend,
  });

  final LanRematchRequest? request;
  final Side side;
  final bool enabled;
  final void Function(LanMessageType, Map<String, Object?>) onSend;

  @override
  Widget build(BuildContext context) {
    final pending = request;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              pending == null
                  ? '沿用当前规则和执棋方，再来一局？'
                  : pending.side == side
                  ? '等待对方同意再来一局…'
                  : '对方邀请你再来一局',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (pending == null)
              FilledButton.icon(
                onPressed: enabled
                    ? () => onSend(LanMessageType.rematchRequest, const {})
                    : null,
                icon: const Icon(Icons.replay),
                label: const Text('再来一局'),
              )
            else if (pending.side != side)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: enabled
                        ? () => onSend(LanMessageType.rematchReject, {
                            'requestSeq': pending.seq,
                          })
                        : null,
                    child: const Text('拒绝'),
                  ),
                  FilledButton(
                    onPressed: enabled
                        ? () => onSend(LanMessageType.rematchAccept, {
                            'requestSeq': pending.seq,
                          })
                        : null,
                    child: const Text('同意'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
