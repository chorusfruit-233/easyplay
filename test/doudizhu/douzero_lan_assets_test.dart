import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:easyplay/doudizhu/multiplayer/card_lan_io.dart';
import 'package:easyplay/doudizhu/multiplayer/card_room_coordinator.dart';
import 'package:easyplay/lan/chess_lan_game.dart';
import 'package:easyplay/lan/lan_transport_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const path = 'douzero/ort-wasm-simd-threaded.mjs';
  for (final cardRoom in [false, true]) {
    test(
      '${cardRoom ? 'card' : 'board'} LAN serves inference modules as JavaScript',
      () async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMessageHandler('flutter/assets', (message) async {
          if (utf8.decode(message!.buffer.asUint8List()) !=
              'assets/web/$path') {
            return null;
          }
          return ByteData.sublistView(
            Uint8List.fromList(utf8.encode('export const module = true;')),
          );
        });
        addTearDown(
          () => messenger.setMockMessageHandler('flutter/assets', null),
        );
        final cards = CardRoomCoordinator(password: 'test');
        final cardServer = CardLanServer(cards);
        final boardServer = LanHostServer(
          chessAuthority: ChessAuthority(),
          token: 'test',
        );
        addTearDown(() async {
          await cardServer.close();
          await cards.close();
          await boardServer.close();
        });
        if (cardRoom) {
          await cardServer.start(host: '127.0.0.1', port: 0);
        } else {
          await boardServer.start(host: '127.0.0.1', port: 0);
        }
        final port = cardRoom ? cardServer.port : boardServer.port;
        await HttpOverrides.runWithHttpOverrides(() async {
          final client = HttpClient();
          try {
            final response = await (await client.getUrl(
              Uri.parse('http://127.0.0.1:$port/$path'),
            )).close();
            expect(response.statusCode, 200);
            expect(
              response.headers.contentType!.mimeType,
              'application/javascript',
            );
            expect(
              await response.transform(utf8.decoder).join(),
              contains('export const'),
            );
          } finally {
            client.close(force: true);
          }
        }, _RealHttp());
      },
    );
  }
}
