import 'dart:async';
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

  testWidgets(
    'leaving before tuning start responds cancels the returned task',
    (tester) async {
      const profile = GoEngineProfile(
        id: 'gpu',
        name: 'GPU',
        backend: GoEngineBackend.opencl,
      );
      final starting = Completer<Map<String, Object?>>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'backendPreflight') {
              return {'runnable': true, 'devices': []};
            }
            if (call.method == 'openclTuningStart') return starting.future;
            if (call.method == 'openclTuningCancel') {
              expect((call.arguments as Map)['id'], 'late-job');
              return {'status': 'cancelled'};
            }
            return null;
          });
      await tester.pumpWidget(
        const MaterialApp(home: GoEngineRuntimePage(profile: profile)),
      );
      await tester.pumpAndSettle();
      final button = find.text('开始 OpenCL 调优');
      await tester.ensureVisible(button);
      await tester.runAsync(() async {
        await tester.tap(button);
        for (
          var i = 0;
          i < 200 && !calls.any((c) => c.method == 'openclTuningStart');
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(calls.any((c) => c.method == 'openclTuningStart'), true);
      await tester.pumpWidget(const SizedBox());
      starting.complete({'id': 'late-job', 'status': 'running'});
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'openclTuningCancel').length, 1);
      expect(calls.any((c) => c.method == 'openclTuningRead'), false);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'OpenCL UI uses native tuning contract and persists verified cache key',
    (tester) async {
      const profile = GoEngineProfile(
        id: 'gpu',
        name: 'GPU',
        backend: GoEngineBackend.opencl,
      );
      await GoEngineLibrary.save(profile);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'backendPreflight':
                return {'runnable': true, 'devices': []};
              case 'openclTuningStart':
                final args = call.arguments as Map;
                expect(args['boardSize'], 19);
                expect(args['model'], isNotEmpty);
                expect(args['config'], contains('rules = chinese'));
                return {'id': 'job', 'tuningId': 'key', 'status': 'running'};
              case 'openclTuningRead':
                return {
                  'id': 'job',
                  'tuningId': 'key',
                  'status': 'completed',
                  'logs': ['GPU tuned'],
                };
            }
            return null;
          });
      await tester.pumpWidget(
        const MaterialApp(home: GoEngineRuntimePage(profile: profile)),
      );
      await tester.pumpAndSettle();
      final button = find.text('开始 OpenCL 调优');
      await tester.ensureVisible(button);
      await tester.runAsync(() async {
        await tester.tap(button);
        for (
          var i = 0;
          i < 200 && !calls.any((c) => c.method == 'openclTuningRead');
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('调优完成'), findsOneWidget);
      expect(find.text('GPU tuned'), findsOneWidget);
      final saved = await GoEngineLibrary.byId(profile.id);
      expect(saved.openclTunedSnapshotKeys, ['key']);
      expect(saved.openclTuningState, GoOpenClTuningState.ready);
      expect(calls.where((c) => c.method == 'openclTuningRead').length, 1);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
