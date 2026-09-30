import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easyplay/chess/chess.dart';
import 'package:easyplay/chess/widgets/chess_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'moving, capturing, undoing and flipping leave no pixels at vacated squares',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = ChessSession();
      final boundary = GlobalKey();
      var flipped = false;
      var generation = 0;
      late StateSetter redraw;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                redraw = setState;
                return Center(
                  child: RepaintBoundary(
                    key: boundary,
                    child: SizedBox.square(
                      dimension: 400,
                      child: ChessBoard(
                        key: ValueKey(generation),
                        session: session,
                        onCell: null,
                        flipped: flipped,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      Future<Uint8List> pixels() async => (await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return Uint8List.fromList(data!.buffer.asUint8List());
      }))!;

      // Compare retained rendering with a freshly mounted board after every
      // transition. This catches ghosts from old layers or stale repaint state.
      Future<void> verify() async {
        await tester.pump();
        final updated = await pixels();
        final last = session.moves.lastOrNull;
        if (last != null) {
          final from = last.from;
          final x = ((flipped ? 7 - from.col : from.col) * 50 + 25);
          final y = ((flipped ? 7 - from.row : from.row) * 50 + 25);
          final offset = (y * 400 + x) * 4;
          final base = (from.row + from.col).isEven
              ? const Color(0xffe7ddc9)
              : const Color(0xff789284);
          final color = Color.lerp(base, Colors.amber, .42)!.toARGB32();
          expect(updated.sublist(offset, offset + 4), [
            (color >> 16) & 255,
            (color >> 8) & 255,
            color & 255,
            255,
          ]);
        }
        redraw(() => generation++);
        await tester.pump();
        expect(await pixels(), orderedEquals(updated));
      }

      for (final move in ['e2e4', 'd7d5', 'e4d5', 'g8f6']) {
        redraw(() => expect(session.applyMove(parseUciMove(move)), isTrue));
        await verify();
      }
      redraw(() => expect(session.undo(), isTrue));
      await verify();
      redraw(() => flipped = true);
      await verify();
      redraw(() => expect(session.undo(), isTrue));
      await verify();
      expect(
        session.position.pieceAt(parseChessSquare('e4'))?.side,
        Side.white,
      );
      expect(
        session.position.pieceAt(parseChessSquare('d5'))?.side,
        Side.black,
      );
    },
  );
}
