// Development oracle inputs only; never included in the application.
// Run: dart run tools/generate_douzero_cases.dart > build/douzero/cases.json
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:easyplay/doudizhu/doudizhu_model.dart';
import 'package:easyplay/doudizhu/doudizhu_rules.dart';
import 'package:easyplay/doudizhu/doudizhu_session.dart';
import 'package:easyplay/doudizhu/ai/douzero_features.dart';
import 'package:easyplay/doudizhu/ai/legal_play_generator.dart';

void main() {
  final cases = <Map<String, Object?>>[];
  for (final landlord in PlayerSeat.values) {
    late DouDizhuSession session;
    for (var seed = 1; ; seed++) {
      session = DouDizhuSession(random: Random(seed));
      session.deal();
      while (session.turn != landlord) {
        session.bid(session.turn, 0);
      }
      session.bid(landlord, 3);
      if (const LegalPlayGenerator()
          .generate(
            session.view(landlord).hand.map(PlayingCard.new).toList(),
            session.trick,
          )
          .any(
            (p) =>
                classifyPlay(p.map(PlayingCard.new).toList())?.type ==
                PlayType.bomb,
          )) {
        break;
      }
    }
    final initialHands = [
      for (final seat in PlayerSeat.values) session.view(seat).hand,
    ];
    void record(String name) {
      final view = session.view(session.turn);
      cases.add({
        'name': 'seat${landlord.index}-$name',
        'initialHands': initialHands,
        'view': view.toWire(),
        'actions': DouZeroFeatures.fromView(view).actions,
      });
    }

    record('initial');
    final openingBomb = const LegalPlayGenerator()
        .generate(
          session.view(landlord).hand.map(PlayingCard.new).toList(),
          session.trick,
        )
        .firstWhere(
          (p) =>
              classifyPlay(p.map(PlayingCard.new).toList())?.type ==
              PlayType.bomb,
        );
    session.play(landlord, [
      session.view(landlord).hand.firstWhere((id) => !openingBomb.contains(id)),
    ]);
    record('down-responds');
    session.pass(session.turn);
    record('up-after-pass');
    session.pass(session.turn);
    record('lead-after-two-passes');
    if (landlord == PlayerSeat.seat0) {
      final bomb = const LegalPlayGenerator()
          .generate(
            session.view(landlord).hand.map(PlayingCard.new).toList(),
            session.trick,
          )
          .where(
            (p) =>
                classifyPlay(p.map(PlayingCard.new).toList())?.type ==
                PlayType.bomb,
          )
          .firstOrNull;
      if (bomb != null) {
        session.play(landlord, bomb);
        record('bomb');
      }
    }
    for (var step = session.publicState.history!.length; step < 21; step++) {
      final view = session.view(session.turn);
      final options = const LegalPlayGenerator().generate(
        view.hand.map(PlayingCard.new).toList(),
        session.trick,
      );
      if (session.trick.seat != null && (step % 5 == 0 || options.isEmpty)) {
        session.pass(session.turn);
      } else {
        session.play(session.turn, options.first);
      }
      if (session.phase != DouDizhuPhase.playing) break;
      if (step == 17) record('long-history');
    }
  }
  stdout.writeln(jsonEncode(cases));
}
