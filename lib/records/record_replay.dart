import '../draughts/draughts_record.dart';
import '../draughts/draughts_result.dart';
import '../draughts/draughts_session.dart';
import '../draughts/draughts_variant.dart';
import '../game_session.dart';
import '../go_record.dart';
import '../gomoku/gomoku_session.dart';
import '../gomoku/gomoku_storage.dart';

/// A projection of a saved record. Replaying never writes to the record store.
class RecordFrame {
  const RecordFrame(
    this.session,
    this.description, {
    this.comment,
    this.annotations = const {},
  });

  final Object session;
  final String description;
  final String? comment;
  final Map<String, List<String>> annotations;
}

abstract class RecordReplay {
  String get title;
  int get length;
  RecordFrame frameAt(int index);

  void checkIndex(int index) {
    if (index < 0 || index > length) {
      throw RangeError.range(index, 0, length, 'index');
    }
  }
}

class GoRecordReplay extends RecordReplay {
  GoRecordReplay(this.sgf, {this.variation = 0}) {
    final parsed = GoSgfController.fromSgf(sgf);
    final leaves = parsed.leaves;
    RangeError.checkValidIndex(variation, leaves, 'variation');
    variations = List.unmodifiable([
      for (var i = 0; i < leaves.length; i++) i == 0 ? '主线' : '变化 $i',
    ]);
    _record = GoSgfController.fromSgf(
      sgf,
      variation: parsed.variationChoices(leaves[variation]),
    );
    _line = _record.path;
  }

  final String sgf;
  final int variation;
  late final List<String> variations;
  late final GoSgfController _record;
  late final List<GoRecordNode> _line;

  @override
  String get title => '围棋棋谱播放';
  @override
  int get length => _line.length - 1;

  @override
  RecordFrame frameAt(int index) {
    checkIndex(index);
    final node = _line[index];
    _record.navigateTo(node);
    final session = _record.replayCurrentPath();
    final move = node.move;
    final description = index == 0
        ? '起始局面 · ${session.size} 路'
        : node.resignedSide != null
        ? '${node.resignedSide!.label}认输'
        : move != null
        ? '${move.side!.label} · ${move.pass ? '停一手' : _coordinate(move.to, session.size, go: true)}'
        : '棋谱注释 / 局面设置';
    return RecordFrame(
      session,
      description,
      comment: node.properties['C']?.join('\n'),
      annotations: node.properties,
    );
  }
}

class GomokuRecordReplay extends RecordReplay {
  GomokuRecordReplay(GomokuRecord record) : _full = record.restore() {
    final state = _full.toJson();
    _actions = List.unmodifiable(
      _full.variant.competitive
          ? (state['actions'] as List).map(GomokuAction.fromJson)
          : _full.moves.map((move) => GomokuAction.place(move.cell)),
    );
  }

  final GomokuSession _full;
  late final List<GomokuAction> _actions;

  @override
  String get title => '五子棋棋谱播放';
  @override
  int get length => _actions.length + (_full.resigned ? 1 : 0);

  @override
  RecordFrame frameAt(int index) {
    checkIndex(index);
    final session = GomokuSession(variant: _full.variant);
    var description = '起始局面 · ${_full.variant.label}';
    for (var i = 0; i < index && i < _actions.length; i++) {
      final action = _actions[i];
      description = switch (action.type) {
        GomokuActionType.exchange =>
          '${session.phase == GomokuPhase.exchange ? '三手交换' : '第二次交换'} · ${action.exchange! ? '交换执棋' : '不交换'}',
        GomokuActionType.declare => '五手打点数 · ${action.count} 个候选点',
        GomokuActionType.pass => '${session.turn.label} · 停一手',
        GomokuActionType.place =>
          '${switch (session.phase) {
            GomokuPhase.proposals => '提出黑5候选',
            GomokuPhase.selection => '选择黑5',
            _ => '${session.turn.label}落子',
          }} · ${_coordinate(action.cell!, session.size)}',
      };
      if (!session.applyAction(action)) {
        throw const FormatException('棋谱包含无法回放的五子棋操作');
      }
    }
    if (_full.resigned && index == length) {
      description = '${_full.winner!.opponent.label}认输';
    }
    return RecordFrame(index == length ? _full.fork() : session, description);
  }
}

class DraughtsRecordReplay extends RecordReplay {
  DraughtsRecordReplay(DraughtsRecord record) : _full = record.restore();

  final DraughtsSession _full;
  bool get _hasEnding =>
      _full.result?.reason == DraughtsEndReason.resignation ||
      _full.result?.reason == DraughtsEndReason.drawAgreement;

  @override
  String get title => '跳棋棋谱播放';
  @override
  int get length => _full.moves.length + (_hasEnding ? 1 : 0);

  @override
  RecordFrame frameAt(int index) {
    checkIndex(index);
    final session = DraughtsSession(_full.rules);
    var description = '起始局面 · ${_full.variant.label}';
    for (var i = 0; i < index && i < _full.moves.length; i++) {
      final move = _full.moves[i];
      description =
          '${session.turn.label} · ${move.path.map((cell) => _coordinate(cell, session.rules.boardSize)).join(' → ')}';
      if (!session.applyMove(move)) {
        throw const FormatException('棋谱包含无法回放的跳棋走法');
      }
    }
    if (_hasEnding && index == length) {
      session.result = _full.result;
      description = _full.result!.isDraw
          ? '双方同意和棋'
          : '${_full.result!.winner!.opponent.label}认输';
    }
    return RecordFrame(
      index == length ? DraughtsSession.fromJson(_full.toJson()) : session,
      description,
    );
  }
}

String _coordinate(Cell cell, int size, {bool go = false}) =>
    '${String.fromCharCode(65 + cell.col + (go && cell.col >= 8 ? 1 : 0))}${size - cell.row}';
