import 'dart:async';
import 'dart:math';

import '../../game_session.dart' show Cell;
import '../gomoku_ai_level.dart';
import '../gomoku_player.dart';
import '../gomoku_rules.dart';
import '../gomoku_session.dart';
import 'rapfi_factory.dart';
import 'rapfi_transport.dart';

class RapfiCancelled implements Exception {
  const RapfiCancelled();
}

/// Gomocup Renju search; the app owns the Soosõrv-8 opening and adjudication.
/// A cancelled synchronous Worker/native search is destroyed before restarting.
class RapfiPlayer implements GomokuPlayer {
  RapfiPlayer({RapfiTransport Function()? transportFactory, Random? random})
    : _factory = transportFactory ?? createRapfiTransport,
      _random = random ?? Random();

  final RapfiTransport Function() _factory;
  final Random _random;
  RapfiTransport? _transport;
  StreamSubscription<String>? _subscription;
  Completer<String>? _pending;
  bool Function(String)? _accept;
  void Function(String)? _observe;
  Future<void> _closing = Future.value();
  int _generation = 0;
  bool _busy = false;
  bool _disposed = false;
  @override
  String? failureReason;

  @override
  void cancel() {
    _generation++;
    _busy = false;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const RapfiCancelled());
    }
    final transport = _transport;
    final subscription = _subscription;
    _transport = null;
    _subscription = null;
    if (transport != null) {
      _closing = _closing
          .then((_) async {
            await subscription?.cancel();
            await transport.close();
          })
          .catchError((Object _) {});
    }
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) throw const RapfiCancelled();
  }

  Future<void> _ensure(int generation) async {
    await _closing;
    _check(generation);
    if (_transport != null) return;
    final transport = _factory();
    _transport = transport;
    _subscription = transport.lines.listen(
      (line) {
        _observe?.call(line);
        final pending = _pending;
        if (pending == null || pending.isCompleted) return;
        if (line.startsWith('ERROR') || line.startsWith('FATAL')) {
          pending.completeError(StateError(line));
        } else if (_accept?.call(line) == true) {
          pending.complete(line);
        }
      },
      onError: (Object error) {
        final pending = _pending;
        if (pending != null && !pending.isCompleted) {
          pending.completeError(error);
        }
      },
    );
    await transport.start();
    _check(generation);
    await _request('START 15', (line) => line == 'OK', generation);
    for (final command in [
      'INFO RULE 4',
      'INFO MAX_MEMORY 33554432',
      'INFO THREAD_NUM 1',
      'INFO PONDERING 0',
      'INFO SWAPABLE 0',
      'INFO USEDATABASE 0',
    ]) {
      await _send(command, generation);
    }
  }

  Future<void> _send(String command, int generation) async {
    _check(generation);
    await _transport!.send(command);
    _check(generation);
  }

  Future<String> _request(
    String command,
    bool Function(String) accept,
    int generation, {
    void Function(String)? observe,
  }) async {
    _check(generation);
    final pending = Completer<String>();
    _pending = pending;
    _accept = accept;
    _observe = observe;
    try {
      // Attach both error handlers before dispatch: a process can fail while
      // the platform send Future is still completing.
      final results = await Future.wait<Object?>([
        pending.future.timeout(const Duration(seconds: 90)),
        _send(command, generation),
      ], eagerError: true);
      _check(generation);
      return results.first! as String;
    } finally {
      if (identical(_pending, pending)) {
        _pending = null;
        _accept = null;
        _observe = null;
      }
    }
  }

  static List<Cell> _legal(GomokuSession session) {
    final flat = session.board.expand((row) => row).toList();
    return [
      for (var row = 0; row < 15; row++)
        for (var col = 0; col < 15; col++)
          if (analyzeGomokuMove(
            flat,
            Cell(row, col),
            session.turn,
            variant: session.variant,
          ).legal)
            Cell(row, col),
    ];
  }

  /// BOARD flags are relative to the searched colour, not the original player.
  /// Rapfi derives black from the first chronological stone. Missing interior
  /// passes are reconstructed from the stone colours; append a trailing pass.
  static String positionCommand(GomokuSession session) => [
    'YXBOARD',
    for (final move in session.moves)
      '${move.cell.col},${move.cell.row},${move.side == session.turn ? 1 : 2}',
    if (session.moves.isNotEmpty && session.moves.last.side == session.turn)
      '-1,-1,2',
    'DONE',
  ].join('\n');

  Future<_Analysis> _query(
    GomokuSession session,
    GomokuAiLevel level,
    int generation, {
    int count = 1,
    List<Cell>? allowed,
    int? milliseconds,
    bool fullStrength = false,
  }) async {
    await _ensure(generation);
    await _send(
      'INFO TIMEOUT_TURN ${milliseconds ?? level.milliseconds}',
      generation,
    );
    await _send(
      'INFO STRENGTH ${fullStrength ? 100 : level.rapfiStrength}',
      generation,
    );
    await _send(positionCommand(session), generation);
    await _send('YXBLOCKRESET', generation);
    final permitted = (allowed ?? _legal(session)).toSet();
    final blocked = [
      for (var row = 0; row < 15; row++)
        for (var col = 0; col < 15; col++)
          if (session.pieceAt(Cell(row, col)) == null &&
              !permitted.contains(Cell(row, col)))
            '$col,$row',
    ];
    if (blocked.isNotEmpty) {
      await _send(['YXBLOCK', ...blocked, 'DONE'].join('\n'), generation);
    }
    final iterations = <int, Map<int, _Candidate>>{};
    List<_Candidate> completed = [];
    final line = await _request(
      'YXNBEST $count',
      (line) => RegExp(r'^\d+,\d+$').hasMatch(line),
      generation,
      observe: (line) {
        final match = RegExp(
          r'^MESSAGE depth (\d+)-\d+(?: multipv (\d+))? ev (\S+).* pv ([A-O])(\d+)',
        ).firstMatch(line);
        if (match == null) return;
        final cell = Cell(
          int.parse(match[5]!) - 1,
          match[4]!.codeUnitAt(0) - 65,
        );
        if (!permitted.contains(cell)) return;
        final value = match[3]!;
        final score =
            int.tryParse(value) ??
            (value.startsWith('+M')
                ? 30000
                : value.startsWith('-M')
                ? -30000
                : null);
        if (score == null) return;
        final iteration = iterations.putIfAbsent(
          int.parse(match[1]!),
          () => {},
        );
        iteration[int.parse(match[2] ?? '1')] = _Candidate(cell, score);
        if (iteration.length == count) {
          completed = iteration.values.toList();
        }
      },
    );
    final coordinates = line.split(',').map(int.parse).toList();
    final best = Cell(coordinates[1], coordinates[0]);
    if (!permitted.contains(best)) throw StateError('Rapfi 返回非法落点');
    // Use a completed MultiPV iteration. Mixing a partly printed next depth
    // can duplicate points and distort the Nth (white-selected) candidate.
    final ranked = completed..sort((a, b) => b.score.compareTo(a.score));
    return _Analysis(best, ranked);
  }

  @override
  Future<GomokuAction?> decide(
    GomokuSession source, {
    GomokuAiLevel level = GomokuAiLevel.intermediate,
  }) async {
    if (_disposed || source.gameOver) return null;
    if (_busy) cancel();
    final generation = ++_generation;
    _busy = true;
    failureReason = null;
    final session = source.fork();
    try {
      switch (session.phase) {
        case GomokuPhase.opening:
          final points = [
            for (var row = 5; row <= 9; row++)
              for (var col = 5; col <= 9; col++)
                if (session.canPlace(Cell(row, col))) Cell(row, col),
          ];
          return GomokuAction.place(points[_random.nextInt(points.length)]);
        case GomokuPhase.exchange:
          // Approximate colour choice after the first three stones. The second
          // choice below also accounts for the declared fifth-point count.
          final result = await _query(
            session,
            level,
            generation,
            fullStrength: true,
          );
          final score = result.candidates.firstOrNull?.score;
          if (score == null) throw StateError('Rapfi 未返回开局评分');
          return GomokuAction.exchange(score < 0); // Searched colour is white.
        case GomokuPhase.declaration:
        case GomokuPhase.secondExchange:
          final result = await _query(
            session,
            level,
            generation,
            count: 8,
            fullStrength: true,
            milliseconds: max(500, level.milliseconds),
          );
          final points = <_Candidate>[];
          for (final candidate in result.candidates) {
            if (points.every(
              (p) => !gomokuEquivalentProposals(
                session.board,
                p.cell,
                candidate.cell,
              ),
            )) {
              points.add(candidate);
            }
          }
          if (session.phase == GomokuPhase.declaration) {
            if (points.isEmpty) throw StateError('Rapfi 未返回候选评分');
            // Black offers its N best inequivalent points; white keeps the
            // weakest one. The second swap makes the closest-to-even N useful.
            var count = 1;
            for (var i = 1; i < points.length; i++) {
              if (points[i].score.abs() < points[count - 1].score.abs()) {
                count = i + 1;
              }
            }
            return GomokuAction.declare(count);
          }
          if (points.length < session.proposalCount) {
            throw StateError('Rapfi 未完成五手候选分析，请重试');
          }
          return GomokuAction.exchange(
            points[session.proposalCount - 1].score < 0,
          );
        case GomokuPhase.selection:
          int? bestScore;
          final choices = <Cell>[];
          for (final cell in session.proposals) {
            final candidate = session.fork()..place(cell);
            final analysis = await _query(
              candidate,
              level,
              generation,
              fullStrength: true,
              milliseconds: max(
                80,
                level.milliseconds ~/ session.proposals.length,
              ),
            );
            final score = analysis.candidates.firstOrNull?.score;
            if (score == null) throw StateError('Rapfi 未返回选点评分');
            if (bestScore == null || score > bestScore) {
              bestScore = score;
              choices.clear();
            }
            if (score == bestScore) choices.add(cell);
          }
          return GomokuAction.place(choices[_random.nextInt(choices.length)]);
        case GomokuPhase.proposals:
          final result = await _query(
            session,
            level,
            generation,
            allowed: _legal(session).where(session.canPlace).toList(),
            fullStrength: true,
          );
          return GomokuAction.place(result.best);
        case GomokuPhase.fourth:
        case GomokuPhase.normal:
          final legal = _legal(session);
          if (legal.isEmpty) {
            return session.canPass ? const GomokuAction.pass() : null;
          }
          final result = await _query(
            session,
            level,
            generation,
            allowed: legal,
          );
          return GomokuAction.place(result.best);
      }
    } on RapfiCancelled {
      return null;
    } catch (error) {
      if (generation == _generation) {
        failureReason = 'Rapfi 思考失败：$error';
        cancel(); // Failed engines are recreated on retry; no silent fallback.
      }
      return null;
    } finally {
      if (generation == _generation) _busy = false;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    cancel();
    await _closing;
  }
}

class _Candidate {
  const _Candidate(this.cell, this.score);
  final Cell cell;
  final int score;
}

class _Analysis {
  const _Analysis(this.best, this.candidates);
  final Cell best;
  final List<_Candidate> candidates;
}
