import 'dart:typed_data';

import '../doudizhu_model.dart';
import '../doudizhu_rules.dart';
import 'legal_play_generator.dart';

/// DouZero-WP observation. Only this seat's view and public actions are used.
class DouZeroFeatures {
  DouZeroFeatures._(this.role, this.actions, this.x, this.z);

  final String role;
  final List<List<int>> actions;
  final Float32List x, z;
  int get width => role == 'landlord' ? 373 : 484;

  factory DouZeroFeatures.fromView(DouDizhuPlayerView view) {
    final state = view.publicState;
    final landlord = state.landlord;
    final history = state.history;
    if (state.phase != DouDizhuPhase.playing ||
        landlord == null ||
        history == null ||
        !view.isTurn ||
        view.hand.isEmpty) {
      throw StateError('DouZero requires a playing view with public history');
    }
    final down = landlord.next, up = down.next;
    final role = view.seat == landlord
        ? 'landlord'
        : view.seat == down
        ? 'landlord_down'
        : 'landlord_up';
    final actions = const LegalPlayGenerator().generate(
      view.hand.map(PlayingCard.new).toList(),
      state.trick,
    );
    if (state.trick.seat != null) actions.add([]);
    if (actions.isEmpty || actions.length > 16384) {
      throw StateError('Invalid DouZero candidate count');
    }
    final played = {for (final seat in PlayerSeat.values) seat: <int>[]};
    final last = {for (final seat in PlayerSeat.values) seat: <int>[]};
    var bombs = 0;
    for (final play in history) {
      played[play.seat]!.addAll(play.cardIds);
      last[play.seat] = play.cardIds;
      final type = classifyPlay(
        play.cardIds.map(PlayingCard.new).toList(),
      )?.type;
      if (type == PlayType.bomb || type == PlayType.rocket) bombs++;
    }
    final known = {...view.hand, ...state.played};
    final unknown = [
      for (var id = 0; id < 54; id++)
        if (!known.contains(id)) id,
    ];
    final common = <double>[
      ..._cards(view.hand),
      ..._cards(unknown),
      if (view.seat == landlord) ...[
        ..._cards(state.trick.cardIds),
        ..._cards(played[up]!),
        ..._cards(played[down]!),
        ..._oneHot(state.counts[up.index] - 1, 17),
        ..._oneHot(state.counts[down.index] - 1, 17),
      ] else ...[
        ..._cards(played[landlord]!),
        ..._cards(played[view.seat == up ? down : up]!),
        ..._cards(state.trick.cardIds),
        ..._cards(last[landlord]!),
        ..._cards(last[view.seat == up ? down : up]!),
        ..._oneHot(state.counts[landlord.index] - 1, 20),
        ..._oneHot(state.counts[(view.seat == up ? down : up).index] - 1, 17),
      ],
      ..._oneHot(bombs, 15),
    ];
    final width = role == 'landlord' ? 373 : 484;
    final x = Float32List(width * actions.length);
    for (var row = 0; row < actions.length; row++) {
      x.setRange(row * width, row * width + common.length, common);
      x.setRange(
        row * width + common.length,
        (row + 1) * width,
        _cards(actions[row]),
      );
    }
    final z = Float32List(15 * 54);
    final recent = history
        .skip(history.length > 15 ? history.length - 15 : 0)
        .toList();
    for (var i = 0; i < recent.length; i++) {
      final start = (15 - recent.length + i) * 54;
      z.setRange(start, start + 54, _cards(recent[i].cardIds));
    }
    return DouZeroFeatures._(
      role,
      List.unmodifiable(actions.map((ids) => List<int>.unmodifiable(ids))),
      x,
      z,
    );
  }
}

List<double> _cards(Iterable<int> ids) {
  final counts = List.filled(15, 0);
  for (final id in ids) {
    if (id < 0 || id >= 54) throw StateError('Invalid card');
    counts[id < 52 ? id ~/ 4 : id - 39]++;
  }
  return [
    for (var rank = 0; rank < 13; rank++)
      for (var copy = 0; copy < 4; copy++) copy < counts[rank] ? 1 : 0,
    counts[13] > 0 ? 1 : 0,
    counts[14] > 0 ? 1 : 0,
  ];
}

List<double> _oneHot(int index, int size) {
  if (index < 0 || index >= size) throw StateError('Invalid DouZero count');
  return [for (var i = 0; i < size; i++) i == index ? 1 : 0];
}
