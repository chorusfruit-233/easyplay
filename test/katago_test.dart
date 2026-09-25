import 'package:flutter_test/flutter_test.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/katago.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled b6 model is present and matches its pinned checksum', () async {
    final bytes = await KataGoCatalog.loadBundledB6();
    expect(bytes.length, greaterThan(3000000));
    expect(
      KataGoDownloadClient.sha256Hex(bytes),
      'f5d32604e3675c480c7c8f6aa579a1ea857135628a0afccc8fa56330fbacd38d',
    );
  });

  test('GTP wrapper sends initialization and extracts responses', () async {
    final commands = <String>[];
    final client = KataGoGtpClient((command) async {
      commands.add(command);
      if (command.startsWith('genmove')) return '= 7\nD4\n\n';
      return '=\n\n';
    });
    await client.initialize(boardSize: 13, komi: 6.5);
    expect(await client.genmove(Side.white), 'D4');
    expect(commands, ['boardsize 13', 'komi 6.5', 'clear_board', 'genmove W']);
  });
}
