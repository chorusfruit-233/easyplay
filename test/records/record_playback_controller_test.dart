import 'package:easyplay/records/record_playback_controller.dart';
import 'package:easyplay/records/record_replay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GoRecordReplay line() => GoRecordReplay('(;GM[1]SZ[9];B[aa];W[bb];B[cc])');

  testWidgets(
    'play, pause, finish, restart and dispose own exactly one timer',
    (tester) async {
      final player = RecordPlaybackController(line());
      expect(player.position, 0);
      expect(player.playing, isFalse);
      player.play();
      player.play();
      await tester.pump(const Duration(seconds: 1));
      expect(player.position, 1);
      player.pause();
      await tester.pump(const Duration(seconds: 3));
      expect(player.position, 1);
      player.play();
      await tester.pump(const Duration(seconds: 2));
      expect(player.position, 3);
      expect(player.playing, isFalse);
      player.play();
      expect(player.position, 0);
      player.dispose();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual seek pauses; speed replaces the pending timer', (
    tester,
  ) async {
    final player = RecordPlaybackController(line());
    addTearDown(player.dispose);
    player.play();
    await tester.pump(const Duration(milliseconds: 400));
    player.setSpeed(2);
    await tester.pump(const Duration(milliseconds: 499));
    expect(player.position, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(player.position, 1);
    player.seek(2);
    expect(player.playing, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(player.position, 2);
    player.seek(999);
    expect(player.position, 3);
    player.seek(-10);
    expect(player.position, 0);
    player.setSpeed(.5);
    player.play();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(player.position, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(player.position, 1);
    player.pause();
  });

  testWidgets('covered route stops without advancing or resuming itself', (
    tester,
  ) async {
    var active = true;
    final player = RecordPlaybackController(line(), canAdvance: () => active);
    addTearDown(player.dispose);
    player.play();
    active = false;
    await tester.pump(const Duration(seconds: 1));
    expect(player.position, 0);
    expect(player.playing, isFalse);
    active = true;
    await tester.pump(const Duration(seconds: 3));
    expect(player.position, 0);
  });

  testWidgets('branch changes pause and invalid branches preserve the view', (
    tester,
  ) async {
    final player = RecordPlaybackController(
      GoRecordReplay('(;GM[1]SZ[9];B[aa](;W[bb])(;W[cc])(;W[aa]))'),
    );
    addTearDown(player.dispose);
    player.play();
    player.selectVariation(1);
    expect(player.playing, isFalse);
    expect(player.position, 0);
    expect((player.record as GoRecordReplay).variation, 1);
    player.seek(player.length);
    final frame = player.frame;
    player.selectVariation(2);
    expect(player.error, contains('无法播放所选变化'));
    expect(player.frame, same(frame));
    expect((player.record as GoRecordReplay).variation, 1);
  });

  testWidgets('empty records keep playback disabled', (tester) async {
    final player = RecordPlaybackController(GoRecordReplay('(;GM[1]SZ[9])'));
    player.play();
    expect(player.playing, isFalse);
    expect(player.position, 0);
    player.dispose();
  });
}
