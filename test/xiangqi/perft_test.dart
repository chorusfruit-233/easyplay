import 'package:easyplay/xiangqi/xiangqi.dart';
import 'package:flutter_test/flutter_test.dart';

// Counts independently obtained with official Pikafish 4c17cee11f888ae1d48a9494f2e2239f019f0a1f:
// position fen <fen>; go perft 2. These positions isolate legs, screens, kings and check.
void main() {
  for (final (fen, nodes) in <(String, int)>[
    ('4k4/9/9/9/9/4P4/9/9/1R7/1N2K4 w - - 0 1', 56),
    ('4k4/9/9/1r7/9/1R2P4/9/1C7/9/4K4 w - - 0 1', 316),
    ('4k4/9/9/4p4/9/4R4/9/9/9/4K4 w - - 0 1', 58),
    ('4k4/9/9/9/9/4P4/9/9/9/r3K4 w - - 0 1', 20),
    ('4k4/3R5/9/9/9/4P4/9/9/9/4K4 w - - 0 1', 37),
  ]) {
    test('native reference perft $fen', () {
      expect(xiangqiPerft(parseXiangqiFen(fen), 2), nodes);
    });
  }
}
