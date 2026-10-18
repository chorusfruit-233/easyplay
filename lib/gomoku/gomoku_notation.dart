import 'dart:convert';

import '../game_session.dart' show Cell, Side;
import 'gomoku_session.dart';
import 'gomoku_storage.dart';

/// Portable stone sequence for SGF readers, and the complete EasyPlay record.
/// SGF has no standard representation for the Soosyrv-8 opening decisions;
/// use the JSON backup when those decisions or a pending opening matter.
class GomokuNotation {
  static String toJson(GomokuRecord record) =>
      '${const JsonEncoder.withIndent('  ').convert(record.toJson())}\n';

  static String fileName(GomokuRecord record, String extension) {
    final date = record.createdAt.toUtc().toIso8601String().replaceAll(
      RegExp('[^0-9TZ]'),
      '',
    );
    final safeId = record.id.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
    final suffix = safeId.length > 48 ? safeId.substring(0, 48) : safeId;
    return 'gomoku_${date}_$suffix.$extension';
  }

  static String toSgf(GomokuRecord record) {
    final session = record.restore();
    final result = StringBuffer('(;GM[4]FF[4]CA[UTF-8]AP[EasyPlay:1]SZ[15]');
    void property(String name, String value) =>
        result.write('$name[${_escape(value)}]');
    property('RU', switch (session.variant) {
      GomokuVariant.soosyrv8 => 'Soosyrv-8',
      GomokuVariant.professional => 'Renju (three-move swap, fifth-move two)',
      GomokuVariant.freestyle => 'Freestyle Gomoku',
      GomokuVariant.standard => 'Standard Gomoku',
      GomokuVariant.renju => 'Renju',
    });
    property('DT', record.createdAt.toUtc().toIso8601String().split('T').first);
    property('PB', _player(record, session.playerForColor(Side.black)));
    property('PW', _player(record, session.playerForColor(Side.white)));
    if (session.gameOver) {
      final winner = session.winner;
      property(
        'RE',
        winner == null
            ? '0'
            : '${winner == Side.black ? 'B' : 'W'}+${session.resigned ? 'R' : ''}',
      );
    }
    property(
      'C',
      '${session.variant.label} · ${session.gameOver ? session.resultLabel : '进行中'}\n'
          '本 SGF 记录正式落子与停着。交换、候选点等开局操作及对局设置请使用 JSON 完整备份。',
    );

    void move(Side side, Cell? cell) {
      result.write(';${side == Side.black ? 'B' : 'W'}[');
      if (cell != null) {
        result.write(String.fromCharCode(97 + cell.col));
        result.write(String.fromCharCode(97 + cell.row));
      }
      result.write(']');
    }

    if (!session.variant.competitive) {
      for (final stone in session.moves) {
        move(stone.side, stone.cell);
      }
    } else {
      // Replaying distinguishes proposed fifth moves from the selected stone,
      // and retains passes even though they are absent from session.moves.
      final replay = GomokuSession(variant: session.variant);
      for (final raw in session.toJson()['actions']! as List) {
        final action = GomokuAction.fromJson(raw);
        final side = replay.turn;
        final count = replay.moves.length;
        if (!replay.applyAction(action)) {
          throw const FormatException('无法导出无效的五子棋操作');
        }
        if (action.type == GomokuActionType.pass) {
          move(side, null);
        } else if (replay.moves.length > count) {
          final stone = replay.moves.last;
          move(stone.side, stone.cell);
        }
      }
    }
    result.writeln(')');
    return result.toString();
  }

  static String _player(GomokuRecord record, Side player) {
    if (record.aiDuel case final config?) {
      return 'AI ${config.levelFor(player).label}';
    }
    if (record.aiLevel case final level?) {
      return player == record.humanSide ? '玩家' : 'AI ${level.label}';
    }
    return player == Side.black ? '开局执黑者' : '开局执白者';
  }

  static String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll(']', r'\]');
}
