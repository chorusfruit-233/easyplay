import 'package:easyplay/battleship/multiplayer/battleship_lan.dart';
import 'package:easyplay/battleship/multiplayer/battleship_room_coordinator.dart';
import 'package:easyplay/lan/lan_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'scanner discovers a Battleship room on its actual dynamic port',
    () async {
      final room = BattleshipRoomCoordinator(password: '1942');
      final server = BattleshipLanServer(room);
      addTearDown(() async {
        await server.close();
        await room.close();
      });
      await server.start(host: '127.0.0.1', port: 0);
      final found = await scanLanTargets(
        ['127.0.0.1'],
        ports: [server.port!],
        timeout: const Duration(seconds: 2),
      );
      expect(found, hasLength(1));
      expect(found.single.game, 'battleship');
      expect(found.single.port, server.port);
      expect(found.single.players, 0);
    },
  );
}
