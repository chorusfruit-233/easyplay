import 'package:easyplay/go_engine_editor.dart';
import 'package:easyplay/go_engine_profiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'editing an engine on a phone preserves rank rules, cfg and tuning metadata',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const profile = GoEngineProfile(
        id: 'edited',
        name: 'GPU config',
        backend: GoEngineBackend.opencl,
        customConfig: 'nnCacheSizePowerOfTwo=18',
        openclTuningState: GoOpenClTuningState.ready,
        openclTunedSnapshotKeys: ['verified'],
        humanOverrideRules: [
          GoEngineOverrideRule(
            id: 'range',
            displayName: '5d 至 6d',
            rankMin: -4,
            rankMax: -5,
            configText: 'maxVisits=120',
          ),
        ],
      );
      await GoEngineLibrary.save(profile);
      // The editor is a sheet in the real app, so host it the same way: a
      // column that keeps the sheet body scrollable under a title.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GoEngineEditor(profile: profile)),
        ),
      );
      await tester.pumpAndSettle();

      // Rename through the name field.
      await tester.enterText(find.byType(TextFormField).first, 'renamed GPU');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      // The cfg text now lives behind the summary card, so open that screen,
      // leave the value alone and come back.
      await tester.ensureVisible(find.text('自定义配置'));
      await tester.tap(find.text('自定义配置'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '合并顺序：内置参数 → 自定义 cfg → 全局/段位规则 → 最终参数覆盖。'
          '棋盘、规则和人类段位以新局设置为准。',
        ),
        findsOneWidget,
      );
      expect(find.text('nnCacheSizePowerOfTwo=18'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      // OpenCL tuning rows are only shown for the OpenCL backend.
      expect(find.text('OpenCL 调优'), findsOneWidget);
      expect(find.text('已调优'), findsNWidgets(2));
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final saved = await GoEngineLibrary.byId(profile.id);
      expect(saved.name, 'renamed GPU');
      expect(saved.customConfig, profile.customConfig);
      expect(saved.humanOverrideRules.single.rankMin, -4);
      expect(saved.humanOverrideRules.single.rankMax, -5);
      expect(saved.humanOverrideRules.single.configText, 'maxVisits=120');
      expect(saved.openclTunedSnapshotKeys, ['verified']);
    },
  );

  testWidgets('the OpenCL section is hidden for the CPU backend', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoEngineEditor(
            profile: const GoEngineProfile(
              id: 'cpu',
              name: 'CPU',
              backend: GoEngineBackend.cpu,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenCL 调优'), findsNothing);
    expect(find.text('重调'), findsNothing);
    // The backend card summarises the current choice. "CPU" can legitimately
    // appear more than once (picker card plus a badge), so assert presence.
    expect(find.text('CPU'), findsWidgets);
  });

  testWidgets('the human model card offers a picker when nothing is chosen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoEngineEditor(
            profile: const GoEngineProfile(
              id: 'plain',
              name: 'Plain',
              backend: GoEngineBackend.cpu,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('点击选择'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });
}
