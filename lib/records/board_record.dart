import 'dart:convert';
import 'dart:math';

import '../chess/chess.dart';
import '../chess/engine/chess_engine.dart';
import '../xiangqi/xiangqi.dart';
import '../xiangqi/engine/xiangqi_engine.dart';

enum BoardRecordGame {
  chess('国际象棋'),
  xiangqi('中国象棋');

  const BoardRecordGame(this.label);
  final String label;
}

enum BoardRecordKind { local, ai, online }

/// An immutable snapshot, including the starting position and external ending.
/// A restored session rebuilds its rule counters and undo history legally.
class BoardGameRecord {
  BoardGameRecord._({
    required this.game,
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    required this.localSide,
    required this.aiLevel,
    required Map<String, Object?> state,
    required this.moveCount,
    required this.gameOver,
    required this.resultLabel,
    required this.score,
  }) : _state = jsonEncode(state);

  factory BoardGameRecord.fromChess(
    ChessSession session, {
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    BoardRecordKind kind = BoardRecordKind.local,
    Side humanSide = Side.white,
    ChessAiLevel? aiLevel,
  }) => BoardGameRecord._(
    game: BoardRecordGame.chess,
    id: id ?? newId(BoardRecordGame.chess),
    kind: kind,
    createdAt: (createdAt ?? DateTime.now()).toUtc(),
    updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    localSide: kind == BoardRecordKind.local ? null : humanSide.name,
    aiLevel: kind == BoardRecordKind.ai
        ? (aiLevel ?? ChessAiLevel.normal).name
        : null,
    state: session.toJson(),
    moveCount: session.moves.length,
    gameOver: session.gameOver,
    resultLabel: session.result?.label ?? '未结束',
    score: !session.gameOver
        ? '*'
        : session.result!.winner == null
        ? '1/2-1/2'
        : session.result!.winner == Side.white
        ? '1-0'
        : '0-1',
  );

  factory BoardGameRecord.fromXiangqi(
    XiangqiSession session, {
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    BoardRecordKind kind = BoardRecordKind.local,
    XiangqiSide humanSide = XiangqiSide.red,
    XiangqiAiLevel? aiLevel,
  }) => BoardGameRecord._(
    game: BoardRecordGame.xiangqi,
    id: id ?? newId(BoardRecordGame.xiangqi),
    kind: kind,
    createdAt: (createdAt ?? DateTime.now()).toUtc(),
    updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    localSide: kind == BoardRecordKind.local ? null : humanSide.name,
    aiLevel: kind == BoardRecordKind.ai
        ? (aiLevel ?? XiangqiAiLevel.normal).name
        : null,
    state: session.toJson(),
    moveCount: session.moves.length,
    gameOver: session.gameOver,
    resultLabel: session.result?.label ?? '未结束',
    score: !session.gameOver
        ? '*'
        : session.result!.winner == null
        ? '1/2-1/2'
        : session.result!.winner == XiangqiSide.red
        ? '1-0'
        : '0-1',
  );

  final BoardRecordGame game;
  final String id;
  final BoardRecordKind kind;
  final DateTime createdAt, updatedAt;
  final String? localSide, aiLevel;
  final int moveCount;
  final bool gameOver;
  final String resultLabel, score;
  final String _state;

  static String newId(BoardRecordGame game) =>
      '${game.name}-${DateTime.now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(0x100000000).toRadixString(16)}';

  ChessSession restoreChess() {
    if (game != BoardRecordGame.chess) throw const FormatException('不是国际象棋棋谱');
    return ChessSession.fromJson(jsonDecode(_state));
  }

  XiangqiSession restoreXiangqi() {
    if (game != BoardRecordGame.xiangqi) {
      throw const FormatException('不是中国象棋棋谱');
    }
    return XiangqiSession.fromJson(jsonDecode(_state));
  }

  Side get chessSide =>
      Side.values.where((s) => s.name == localSide).firstOrNull ?? Side.white;
  XiangqiSide get xiangqiSide =>
      XiangqiSide.values.where((s) => s.name == localSide).firstOrNull ??
      XiangqiSide.red;
  ChessAiLevel get chessLevel =>
      ChessAiLevel.values.firstWhere((level) => level.name == aiLevel);
  XiangqiAiLevel get xiangqiLevel =>
      XiangqiAiLevel.values.firstWhere((level) => level.name == aiLevel);
  String get modeLabel => switch (kind) {
    BoardRecordKind.local => '本地双人',
    BoardRecordKind.online => '联机',
    BoardRecordKind.ai =>
      '人机 · ${game == BoardRecordGame.chess ? chessLevel.displayLabel : xiangqiLevel.displayLabel}',
  };

  Map<String, Object?> toJson() => {
    'version': 1,
    'game': game.name,
    'id': id,
    'kind': kind.name,
    'localSide': localSide,
    'aiLevel': aiLevel,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'session': jsonDecode(_state),
  };

  /// Import as a separate entry; a backup never overwrites an active game.
  BoardGameRecord importedCopy() => BoardGameRecord.fromJson({
    ...toJson(),
    'id': newId(game),
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  });

  factory BoardGameRecord.fromJson(Object? value) {
    Never invalid() => throw const FormatException('无效或不支持的棋谱备份');
    if (value is! Map ||
        value['version'] != 1 ||
        value['id'] is! String ||
        !RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(value['id'] as String)) {
      invalid();
    }
    final game = BoardRecordGame.values
        .where((g) => g.name == value['game'])
        .firstOrNull;
    final kind = BoardRecordKind.values
        .where((k) => k.name == value['kind'])
        .firstOrNull;
    final created = DateTime.tryParse(value['createdAt']?.toString() ?? '');
    final updated = DateTime.tryParse(value['updatedAt']?.toString() ?? '');
    if (game == null || kind == null || created == null || updated == null) {
      invalid();
    }
    final side = value['localSide'], level = value['aiLevel'];
    if (kind == BoardRecordKind.local && side != null ||
        kind != BoardRecordKind.ai && level != null) {
      invalid();
    }
    final state = value['session'];
    if (state is! Map ||
        state['version'] != 1 ||
        state['game'] != game.name ||
        state['initialFen'] is! String ||
        state['moves'] is! List ||
        (state['moves'] as List).length > 10000 ||
        (state['moves'] as List).any((m) => m is! String) ||
        state.keys.any((key) => key is! String)) {
      invalid();
    }
    String label = '未结束', score = '*';
    final ending = state['result'];
    if (ending != null && ending is! Map) invalid();
    if (game == BoardRecordGame.chess) {
      final human = Side.values.where((s) => s.name == side).firstOrNull;
      final ai = ChessAiLevel.values.where((l) => l.name == level).firstOrNull;
      if (state['rulesVersion'] != chessRulesVersion ||
          kind != BoardRecordKind.local && human == null ||
          kind == BoardRecordKind.ai && ai == null) {
        invalid();
      }
      if (ending is Map) {
        final reason = ChessEndReason.values
            .where((r) => r.name == ending['reason'])
            .firstOrNull;
        final winner = Side.values
            .where((s) => s.name == ending['winner'])
            .firstOrNull;
        if (reason == null ||
            ending['winner'] != null && winner == null ||
            [
                  ChessEndReason.checkmate,
                  ChessEndReason.resignation,
                ].contains(reason) !=
                (winner != null)) {
          invalid();
        }
        label = ChessResult(reason: reason, winner: winner).label;
        score = winner == null
            ? '1/2-1/2'
            : winner == Side.white
            ? '1-0'
            : '0-1';
      }
    } else {
      final human = XiangqiSide.values.where((s) => s.name == side).firstOrNull;
      final ai = XiangqiAiLevel.values
          .where((l) => l.name == level)
          .firstOrNull;
      if (state['rulesVersion'] != xiangqiRulesVersion ||
          state['ruleProfile'] != xiangqiRuleProfile ||
          kind != BoardRecordKind.local && human == null ||
          kind == BoardRecordKind.ai && ai == null) {
        invalid();
      }
      if (ending is Map) {
        final reason = XiangqiEndReason.values
            .where((r) => r.name == ending['reason'])
            .firstOrNull;
        final winner = XiangqiSide.values
            .where((s) => s.name == ending['winner'])
            .firstOrNull;
        if (reason == null ||
            ending['winner'] != null && winner == null ||
            [
                  XiangqiEndReason.checkmate,
                  XiangqiEndReason.noLegalMove,
                  XiangqiEndReason.resignation,
                  XiangqiEndReason.repetitionViolation,
                ].contains(reason) !=
                (winner != null)) {
          invalid();
        }
        label = XiangqiResult(reason: reason, winner: winner).label;
        score = winner == null
            ? '1/2-1/2'
            : winner == XiangqiSide.red
            ? '1-0'
            : '0-1';
      }
    }
    // Listing and autosaving must not legally replay every historical game.
    // Restore validates the full sequence before continuing, playing or import.
    return BoardGameRecord._(
      game: game,
      id: value['id'] as String,
      kind: kind,
      createdAt: created.toUtc(),
      updatedAt: updated.toUtc(),
      localSide: side as String?,
      aiLevel: level as String?,
      state: Map<String, Object?>.from(state),
      moveCount: (state['moves'] as List).length,
      gameOver: ending != null,
      resultLabel: label,
      score: score,
    );
  }
}
