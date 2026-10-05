import 'package:flutter/foundation.dart';
import 'doudizhu.dart';
import 'multiplayer/doudizhu_replica.dart';

/// Widgets never receive the full network authority or opponents' hands.
class DouDizhuMatchController extends ChangeNotifier {
  DouDizhuMatchController.network(this.replica) : _local = null {
    replica!.addListener(_update);
  }
  DouDizhuMatchController.hotseat()
    : replica = null,
      _local = DouDizhuSession() {
    _local!.deal();
    covered = true;
  }
  final DouDizhuReplica? replica;
  final DouDizhuSession? _local;
  bool covered = false;
  int _revision = 0;
  bool get hotseat => _local != null;
  bool get connected => hotseat || replica!.connected;
  bool get canAct =>
      connected &&
      (hotseat || replica!.seats.every((s) => s['connected'] == true));
  int get revision => hotseat ? _revision : replica!.seq;
  PublicGameState? get state =>
      _local?.publicState ?? replica?.view?.publicState;
  DouDizhuPlayerView? get view =>
      hotseat ? (covered ? null : _local!.view(_local.turn)) : replica!.view;
  String? get error => replica?.error;
  void _update() => notifyListeners();
  void reveal() {
    covered = false;
    _revision++;
    notifyListeners();
  }

  void act(String action, [Map<String, Object?> p = const {}]) {
    if (!hotseat) {
      replica!.send(action, p);
      return;
    }
    if (covered && action != 'rematch') throw StateError('请先确认接过设备');
    switch (action) {
      case 'bid':
        _local!.bid(_local.turn, p['score'] as int);
      case 'play':
        _local!.play(_local.turn, (p['cards'] as List).cast<int>());
      case 'pass':
        _local!.pass(_local.turn);
      case 'rematch':
        _local!.deal();
      default:
        throw StateError('操作无效');
    }
    covered = _local.phase != DouDizhuPhase.finished;
    _revision++;
    notifyListeners();
  }

  Future<List<int>> hint() async {
    final current = view;
    if (current == null || !current.isTurn) return [];
    return const DouDizhuAi().chooseAsync(current);
  }

  @override
  void dispose() {
    replica?.removeListener(_update);
    _local?.close();
    super.dispose();
  }
}
