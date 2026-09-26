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
      await tester.pumpWidget(
        const MaterialApp(home: GoEngineEditor(profile: profile)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'renamed GPU');
      tester.testTextInput.hide();
      await tester.scrollUntilVisible(
        find.text('保存配置'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('保存配置'));
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
}
