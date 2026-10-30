import 'dart:convert';

import '../chess/chess.dart';
import '../xiangqi/xiangqi.dart';
import 'board_record.dart';

class BoardRecordNotation {
  static String toJson(BoardGameRecord record) =>
      const JsonEncoder.withIndent('  ').convert(record.toJson());

  static BoardGameRecord importJson(String text, BoardRecordGame game) {
    if (utf8.encode(text).length > 5 * 1024 * 1024) {
      throw const FormatException('棋谱文件超过 5 MB');
    }
    final record = BoardGameRecord.fromJson(jsonDecode(text));
    if (record.game != game) throw FormatException('请选择${game.label}棋谱');
    if (game == BoardRecordGame.chess) {
      record.restoreChess().dispose();
    } else {
      record.restoreXiangqi().dispose();
    }
    return record.importedCopy();
  }

  static String fileName(BoardGameRecord record, String extension) {
    final date = record.createdAt.toUtc().toIso8601String().replaceAll(
      RegExp('[-:.]'),
      '',
    );
    return '${record.game.name}_${date}_${record.id}.$extension';
  }

  static String _tag(String name, String value) =>
      '[$name "${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll(RegExp(r'[\r\n]'), ' ')}"]';

  static String toPgn(BoardGameRecord record) {
    final full = record.restoreChess();
    final replay = ChessSession(position: full.initialPosition);
    final date = record.createdAt
        .toUtc()
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '.');
    String player(Side side) =>
        record.kind == BoardRecordKind.ai && side != record.chessSide
        ? 'Stockfish 19 (${record.chessLevel.label})'
        : side == Side.white
        ? 'White'
        : 'Black';
    final tags = [
      _tag('Event', 'EasyPlay'),
      _tag('Site', 'Local'),
      _tag('Date', date),
      _tag('Round', '-'),
      _tag('White', player(Side.white)),
      _tag('Black', player(Side.black)),
      _tag('Result', record.score),
      if (full.initialFen != exportFen(ChessPosition.initial())) ...[
        _tag('SetUp', '1'),
        _tag('FEN', full.initialFen),
      ],
      if (full.result != null)
        _tag('EasyPlayEndReason', full.result!.reason.name),
    ];
    final tokens = <String>[];
    for (var i = 0; i < full.moves.length; i++) {
      if (replay.turn == Side.white) {
        tokens.add('${replay.position.fullmoveNumber}.');
      } else if (i == 0) {
        tokens.add('${replay.position.fullmoveNumber}...');
      }
      final move = full.moves[i];
      tokens.add(chessSan(replay, move));
      if (!replay.applyMove(move)) throw const FormatException('无法导出非法着法');
    }
    tokens.add(record.score);
    return '${tags.join('\n')}\n\n${tokens.join(' ')}\n';
  }

  /// Plain ICCS coordinate text keeps Chinese Chess distinct from chess PGN.
  static String toIccs(BoardGameRecord record) {
    final session = record.restoreXiangqi();
    final out = StringBuffer()
      ..writeln('EasyPlay 中国象棋 · ICCS 坐标着法')
      ..writeln('日期：${record.createdAt.toUtc().toIso8601String()}')
      ..writeln('规则：$xiangqiRuleProfile / $xiangqiRulesVersion')
      ..writeln('初始 FEN：${session.initialFen}')
      ..writeln('结果：${record.score} · ${record.resultLabel}')
      ..writeln();
    for (var i = 0; i < session.moves.length; i++) {
      final move = session.moves[i];
      out.writeln(
        '${i + 1}. ${xiangqiSquare(move.from).toUpperCase()}-${xiangqiSquare(move.to).toUpperCase()}',
      );
    }
    return out.toString();
  }
}

/// Standard algebraic notation is based on legal alternatives (pinned pieces
/// must not force disambiguation). The caller retains ownership of the session.
String chessSan(ChessSession session, ChessMove move) {
  if (!session.isLegalMove(move)) throw const FormatException('非法国际象棋着法');
  final piece = session.position.pieceAt(move.from)!;
  final capture =
      session.position.pieceAt(move.to) != null ||
      piece.type == ChessPieceType.pawn && move.from.col != move.to.col;
  String san;
  if (piece.type == ChessPieceType.king &&
      (move.from.col - move.to.col).abs() == 2) {
    san = move.to.col == 6 ? 'O-O' : 'O-O-O';
  } else {
    var disambiguation = '';
    if (piece.type != ChessPieceType.pawn) {
      final others = session
          .legalMoves()
          .where(
            (candidate) =>
                candidate.from != move.from &&
                candidate.to == move.to &&
                session.position.pieceAt(candidate.from)?.type == piece.type,
          )
          .toList();
      if (others.isNotEmpty) {
        final file = chessSquare(move.from)[0],
            rank = chessSquare(move.from)[1];
        disambiguation = others.every((m) => m.from.col != move.from.col)
            ? file
            : others.every((m) => m.from.row != move.from.row)
            ? rank
            : '$file$rank';
      }
    } else if (capture) {
      disambiguation = chessSquare(move.from)[0];
    }
    san =
        '${piece.type == ChessPieceType.pawn ? '' : 'PNBRQK'[piece.type.index]}'
        '$disambiguation${capture ? 'x' : ''}${chessSquare(move.to)}'
        '${move.promotion == null ? '' : '=${'PNBRQK'[move.promotion!.index]}'}';
  }
  final after = ChessMoveGenerator.applyUnchecked(session.position, move);
  if (ChessMoveGenerator.isInCheck(after, after.sideToMove)) {
    san += ChessMoveGenerator.legalMoves(after).isEmpty ? '#' : '+';
  }
  return san;
}
