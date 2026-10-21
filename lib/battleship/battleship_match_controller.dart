import 'dart:async';

import 'package:flutter/foundation.dart';

import 'battleship.dart';
import 'multiplayer/battleship_replica.dart';

/// Owns local authority or a single recipient's network view, never both.
class BattleshipMatchController extends ChangeNotifier {
  BattleshipMatchController.singlePlayer({
    BattleshipSeat human = BattleshipSeat.player1,
    this.aiDelay = const Duration(milliseconds: 550),
  }) : _local = BattleshipSession(),
       _replica = null,
       _human = human,
       _viewer = human,
       hotseat = false {
    _prepareAiFleet();
  }

  BattleshipMatchController.hotseat()
    : _local = BattleshipSession(),
      _replica = null,
      _human = null,
      _viewer = BattleshipSeat.player1,
      hotseat = true,
      aiDelay = Duration.zero,
      _covered = true;

  BattleshipMatchController.network(BattleshipReplica replica)
    : _local = null,
      _replica = replica,
      _human = null,
      _viewer = BattleshipSeat.player1,
      hotseat = false,
      aiDelay = Duration.zero {
    replica.addListener(_networkChanged);
  }

  final BattleshipSession? _local;
  final BattleshipReplica? _replica;
  final BattleshipSeat? _human;
  final bool hotseat;
  final Duration aiDelay;
  final _ai = BattleshipAi();
  BattleshipSeat _viewer;
  bool _covered = false, _disposed = false, _active = true;
  int _revision = 0, _generation = 0;
  Timer? _aiTimer;
  String? _aiError;

  bool get covered => _covered;
  BattleshipSeat get handoffSeat => _replica?.view?.seat ?? _viewer;
  BattleshipPlayerView? get view =>
      covered ? null : _local?.view(_viewer) ?? _replica?.view;
  BattleshipPhase? get phase => _local?.phase ?? _replica?.view?.phase;
  List<BattleshipShot> get shots =>
      _local?.view(_viewer).shots ?? _replica?.view?.shots ?? const [];
  int get revision => _replica?.seq ?? _revision;
  String? get error => _replica?.error ?? _aiError;
  bool get connected =>
      _replica == null ||
      (_replica.connected &&
          _replica.started &&
          _replica.seats.length == 2 &&
          _replica.seats.every((seat) => seat['connected'] == true));
  bool get thinking =>
      _human != null &&
      _local!.phase == BattleshipPhase.playing &&
      _local.turn != _human;
  bool get canAct => connected && !covered && !thinking && _active;
  bool get rematchPending =>
      _replica?.rematch.contains(_replica.view?.seat.index) ?? false;
  bool get canReconnect => _replica?.reconnect != null;

  void _networkChanged() {
    if (!_disposed) notifyListeners();
  }

  void _prepareAiFleet() {
    if (_human == null) return;
    final seat = _human.opponent;
    _local!
      ..randomizeFleet(seat)
      ..ready(seat);
  }

  void _cancelAi() {
    _generation++;
    _aiTimer?.cancel();
    _aiTimer = null;
  }

  void _scheduleAi() {
    _cancelAi();
    if (_disposed || !_active || !thinking || _aiError != null) return;
    final generation = _generation;
    _aiTimer = Timer(aiDelay, () {
      _aiTimer = null;
      if (_disposed || !_active || generation != _generation || !thinking) {
        return;
      }
      try {
        final seat = _human!.opponent;
        final cell = _ai.choose(_local!.view(seat));
        _local.fire(seat, cell);
        _revision++;
      } catch (_) {
        _aiError = 'AI 暂时未能出手，请重试';
      }
      if (!_disposed) notifyListeners();
    });
  }

  /// Cancels pending work while the app is away and reschedules once on return.
  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    // A local handoff remains private when the OS previews the app or the
    // player returns from another route. Revealing always requires consent.
    if (!active && hotseat && phase != BattleshipPhase.finished) {
      _covered = true;
    }
    _scheduleAi();
    notifyListeners();
  }

  void retryAi() {
    if (_disposed) return;
    _aiError = null;
    _scheduleAi();
    notifyListeners();
  }

  Future<void> reconnect() async {
    await _replica?.reconnect?.call();
  }

  void reveal() {
    if (_disposed || !_active || !hotseat || !covered) return;
    _covered = false;
    _revision++;
    notifyListeners();
  }

  void _act(
    String action,
    Map<String, Object?> payload,
    void Function(BattleshipSession, BattleshipSeat) apply, {
    bool handoff = false,
  }) {
    if (_disposed) throw StateError('对局已关闭');
    if (!canAct) throw StateError(covered ? '请先确认接过设备' : '请等待当前回合或恢复连接');
    if (_replica != null) {
      _replica.send(action, payload);
      return;
    }
    final actor = _viewer;
    apply(_local!, actor);
    _revision++;
    if (hotseat && handoff && _local.phase != BattleshipPhase.finished) {
      _viewer = _local.phase == BattleshipPhase.placement
          ? actor.opponent
          : _local.turn;
      _covered = true;
    }
    _scheduleAi();
    notifyListeners();
  }

  void place(ShipPlacement placement) => _act(
    'place',
    placement.toWire(),
    (session, seat) => session.place(seat, placement),
  );
  void remove(ShipType ship) => _act('remove', {
    'ship': ship.name,
  }, (session, seat) => session.remove(seat, ship));
  void randomize() => _act(
    'randomize',
    const {},
    (session, seat) => session.randomizeFleet(seat),
  );
  void clear() =>
      _act('clear', const {}, (session, seat) => session.clearFleet(seat));
  void ready() => _act(
    'ready',
    const {},
    (session, seat) => session.ready(seat),
    handoff: true,
  );
  void fire(int cell) => _act(
    'fire',
    {'cell': cell},
    (session, seat) => session.fire(seat, cell),
    handoff: true,
  );
  void resign() =>
      _act('resign', const {}, (session, seat) => session.resign(seat));

  void rematch() {
    if (_disposed) throw StateError('对局已关闭');
    if (!connected || !_active || phase != BattleshipPhase.finished) {
      throw StateError('请在对局结束后再来一局');
    }
    if (_replica != null) {
      if (!rematchPending) _replica.send('rematch');
      return;
    }
    _cancelAi();
    _local!.reset();
    _aiError = null;
    _viewer = _human ?? BattleshipSeat.player1;
    _covered = hotseat;
    _prepareAiFleet();
    _revision++;
    _scheduleAi();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAi();
    _replica?.removeListener(_networkChanged);
    super.dispose();
  }
}
