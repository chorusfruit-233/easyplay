import 'package:easyplay/doudizhu/doudizhu_model.dart';
import 'package:easyplay/doudizhu/doudizhu_table.dart';
import 'package:easyplay/doudizhu/widgets/doudizhu_card.dart';
import 'package:easyplay/doudizhu/widgets/doudizhu_played_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'public cards fit narrow slots with twenty cards and large text',
    (tester) async {
      final plays = [
        DouDizhuSeatPlay([
          for (var rank = 0; rank < 5; rank++)
            for (var suit = 0; suit < 3; suit++) rank * 4 + suit,
          20,
          24,
          28,
          32,
          36,
        ]),
        DouDizhuSeatPlay([52, 53]),
        DouDizhuSeatPlay([], passed: true),
      ];
      for (final width in [110.0, 240.0]) {
        for (final scale in [1.0, 1.6]) {
          for (final play in plays) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: DouDizhuPlayedCards(
                          seat: PlayerSeat.seat0,
                          play: play,
                          complete: true,
                          strongest: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            expect(find.byType(DouDizhuCard), findsNWidgets(play.cards.length));
            final bounds = tester.getRect(find.byType(DouDizhuPlayedCards));
            for (final card in find.byType(DouDizhuCard).evaluate()) {
              final rect = tester.getRect(find.byWidget(card.widget));
              expect(bounds.contains(rect.topLeft), isTrue);
              expect(bounds.contains(rect.bottomRight), isTrue);
            }
            expect(find.byType(GestureDetector), findsNothing);
          }
        }
      }
    },
  );
}
