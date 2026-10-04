import '../game_session.dart' show Cell;
import 'xiangqi_fen.dart';
import 'xiangqi_move.dart';
import 'xiangqi_move_generator.dart';
import 'xiangqi_position.dart';
import 'xiangqi_repetition.dart';
import 'xiangqi_result.dart';
import 'xiangqi_rules.dart';
import 'xiangqi_side.dart';

const xiangqiRulesVersion = XiangqiRules.version;
const xiangqiRuleProfile = XiangqiRules.profile;

class _Snapshot {
  _Snapshot(
    this.position,
    this.result,
    this.moveCount,
    this.rule60,
    Map<XiangqiSide, int> checks,
  ) : checks = Map.of(checks);
  final XiangqiPosition position;
  final XiangqiResult? result;
  final int moveCount, rule60;
  final Map<XiangqiSide, int> checks;
}

/// Sole rules authority; all history remains temporary and is never persisted.
class XiangqiSession {
  XiangqiSession({XiangqiPosition? position})
    : initialPosition = position ?? XiangqiPosition.initial() {
    _position = initialPosition;
    _rule60 = _position.halfmoveClock;
    _adjudicate();
  }
  final XiangqiPosition initialPosition;
  late XiangqiPosition _position;
  XiangqiResult? _result;
  final _moves = <XiangqiMove>[];
  final _history = <XiangqiMoveRecord>[];
  final _undo = <_Snapshot>[];
  final _checks = {XiangqiSide.red: 0, XiangqiSide.black: 0};
  int _rule60 = 0, _revision = 0;
  XiangqiPosition get position => _position;
  XiangqiResult? get result => _result;
  XiangqiSide get turn => position.sideToMove;
  List<XiangqiMove> get moves => List.unmodifiable(_moves);
  List<XiangqiMoveRecord> get repetitionHistory => List.unmodifiable(_history);
  bool get gameOver => result != null;
  bool get canUndo => _undo.isNotEmpty;
  int get revision => _revision;
  int get noCapturePlies => _rule60;
  String get fen => exportXiangqiFen(position);
  String get initialFen => exportXiangqiFen(initialPosition);
  String get status =>
      result?.label ?? '${turn.label}回合${isInCheck(turn) ? ' · 将军' : ''}';
  bool isInCheck(XiangqiSide side) =>
      XiangqiMoveGenerator.isInCheck(position, side);
  List<XiangqiMove> legalMoves() =>
      gameOver ? [] : XiangqiMoveGenerator.legalMoves(position);
  List<XiangqiMove> legalMovesFrom(Cell from) =>
      gameOver ? [] : XiangqiMoveGenerator.legalMoves(position, from: from);
  bool isLegalMove(XiangqiMove move) =>
      legalMovesFrom(move.from).contains(move);
  void _save() =>
      _undo.add(_Snapshot(position, result, moves.length, _rule60, _checks));
  bool applyMove(XiangqiMove move) {
    if (!isLegalMove(move)) return false;
    _save();
    final before = position, side = turn, piece = before.pieceAt(move.from)!;
    final captured = before.pieceAt(move.to);
    var after = XiangqiMoveGenerator.applyUnchecked(before, move);
    final check = XiangqiMoveGenerator.isInCheck(after, side.opponent);
    final chase = check || captured != null
        ? <int>{}
        : XiangqiRepetition.chased(
            after,
            side,
          ).difference(XiangqiRepetition.chased(before, side));
    if (captured != null) {
      _rule60 = 0;
      _checks.updateAll((_, _) => 0);
    } else {
      if (check) _checks[side] = _checks[side]! + 1;
      if (!check || _checks[side]! <= XiangqiRules.countedChecksPerSide) {
        if (_checks[side.opponent]! > XiangqiRules.countedChecksPerSide &&
            _history.lastOrNull?.gaveCheck == true) {
          _checks[side.opponent] = _checks[side.opponent]! + 1;
        } else {
          _rule60++;
        }
      }
    }
    after = XiangqiPosition(
      board: after.board,
      sideToMove: after.sideToMove,
      halfmoveClock: _rule60,
      fullmoveNumber: after.fullmoveNumber,
    );
    _position = after;
    _moves.add(move);
    _history.add(
      XiangqiMoveRecord(
        before: before,
        after: after,
        move: move,
        piece: piece,
        captured: captured,
        gaveCheck: check,
        chasedIds: chase,
      ),
    );
    _revision++;
    _adjudicate();
    return true;
  }

  void _adjudicate() {
    if (XiangqiMoveGenerator.legalMoves(position).isEmpty) {
      _result = XiangqiResult(
        winner: turn.opponent,
        reason: isInCheck(turn)
            ? XiangqiEndReason.checkmate
            : XiangqiEndReason.noLegalMove,
      );
      return;
    }
    final repetition = XiangqiRepetition().evaluate(position, _history);
    if (repetition != null) {
      _result = XiangqiResult(
        winner: repetition.offender?.opponent,
        reason: repetition.isDraw
            ? XiangqiEndReason.repetitionDraw
            : XiangqiEndReason.repetitionViolation,
      );
    } else if (_rule60 >= XiangqiRules.noCapturePlies) {
      _result = const XiangqiResult(reason: XiangqiEndReason.moveLimitDraw);
    }
  }

  bool resign(XiangqiSide side) {
    if (gameOver) return false;
    _save();
    _result = XiangqiResult(
      winner: side.opponent,
      reason: XiangqiEndReason.resignation,
    );
    _revision++;
    return true;
  }

  bool agreeDraw() {
    if (gameOver) return false;
    _save();
    _result = const XiangqiResult(reason: XiangqiEndReason.drawAgreement);
    _revision++;
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    final snap = _undo.removeLast();
    _position = snap.position;
    _result = snap.result;
    _moves.length = snap.moveCount;
    _history.length = snap.moveCount;
    _rule60 = snap.rule60;
    _checks
      ..clear()
      ..addAll(snap.checks);
    _revision++;
    return true;
  }

  void reset() {
    _position = initialPosition;
    _result = null;
    _moves.clear();
    _history.clear();
    _undo.clear();
    _checks.updateAll((_, _) => 0);
    _rule60 = initialPosition.halfmoveClock;
    _revision++;
    _adjudicate();
  }

  XiangqiSession fork() {
    final copy = XiangqiSession(position: initialPosition);
    copy._position = position;
    copy._result = result;
    copy._moves.addAll(_moves);
    copy._history.addAll(_history);
    copy._undo.addAll(_undo);
    copy._checks
      ..clear()
      ..addAll(_checks);
    copy._rule60 = _rule60;
    copy._revision = _revision;
    return copy;
  }

  void dispose() {
    _moves.clear();
    _history.clear();
    _undo.clear();
  }
}
