import 'dart:async';
import 'dart:convert';
import 'package:easyplay/go_models.dart';
import 'package:easyplay/game_session.dart';
import 'package:easyplay/go_engine_profiles.dart';
import 'package:easyplay/go_engine_runtime.dart';
import 'package:easyplay/katago.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('easyplay/katago');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Android large model arguments never load bytes through the channel',
    () async {
      final id = List.filled(64, 'a').join();
      final model = GoModelInfo(
        id: id,
        name: 'large human',
        fileName: 'human.txt.gz',
        sha256: id,
        bytes: 131000000,
        kind: GoModelKind.human,
      );
      SharedPreferences.setMockInitialValues({
        'easyplay.katago_models': [jsonEncode(model.toJson())],
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            fail('Model bytes must stay native: ${call.method}');
          });
      expect(
        await GoModelLibrary.androidModelArguments(id, prefix: 'humanModel'),
        {'humanModelId': id, 'humanModelFileName': 'human.txt.gz'},
      );
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            expect(call.arguments, {'id': id});
            return 'verified';
          });
      await GoModelLibrary.validateAvailable(id);
      expect(calls, ['validateModel']);
      await expectLater(
        GoModelLibrary.androidModelArguments('missing'),
        throwsStateError,
      );
    },
  );

  test(
    'stop interrupts a pending search without waiting in the GTP queue',
    () async {
      final search = Completer<String>();
      final called = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            called.add(call.method);
            if (call.method == 'command' &&
                (call.arguments as Map)['line'] == 'genmove B') {
              return search.future;
            }
            if (call.method == 'stop') {
              search.complete('D4');
              return 'stopped';
            }
            return call.method == 'start' ? 'ready' : '';
          });
      final runtime = KataGoAndroidRuntime();
      await runtime.start(config: const GoConfig());
      final move = runtime.send('genmove B');
      await Future<void>.delayed(Duration.zero);
      await runtime.stop().timeout(const Duration(seconds: 2));
      expect(called.last, 'stop');
      expect(runtime.isStarted, false);
      await move;
    },
  );

  testWidgets('CPU availability and diagnostics never transfer models', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'backendPreflight') {
            expect(call.arguments, {'backend': 'cpu'});
            return {'runnable': true};
          }
          return {
            'backend': 'cpu',
            'logs': ['ready'],
          };
        });
    await tester.pumpWidget(
      const MaterialApp(
        home: GoEngineRuntimePage(profile: GoEngineProfile.builtIn),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CPU 引擎可用'), findsOneWidget);
    await tester.tap(find.text('读取日志'));
    await tester.pumpAndSettle();
    expect(calls, ['backendPreflight', 'diagnostics']);
    expect(find.textContaining('ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
