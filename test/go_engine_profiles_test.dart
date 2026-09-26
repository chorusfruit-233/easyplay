import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyplay/go_engine_profiles.dart';
import 'package:easyplay/go_human_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saves, selects, and removes custom engine profiles', () async {
    final profile = GoEngineProfile(
      id: 'custom-1',
      name: '低功耗',
      maxTimeSeconds: 5,
      searchThreads: 1,
      configOverrides: 'maxVisits = 80',
    );
    await GoEngineLibrary.save(profile);
    await GoEngineLibrary.setActive(profile.id);

    expect(await GoEngineLibrary.activeId(), profile.id);
    final loaded = await GoEngineLibrary.byId(profile.id);
    expect(loaded.name, profile.name);
    expect(loaded.searchThreads, profile.searchThreads);
    expect(loaded.configOverrides, profile.configOverrides);
    await GoEngineLibrary.remove(profile.id);
    expect(await GoEngineLibrary.activeId(), GoEngineProfile.builtIn.id);
  });

  test('rejects malformed config overrides and out-of-range engine values', () {
    expect(
      () => GoEngineLibrary.validateOverrides('maxVisits'),
      throwsArgumentError,
    );
    expect(
      () => GoEngineLibrary.save(
        const GoEngineProfile(id: 'bad', name: 'bad', searchThreads: 99),
      ),
      throwsArgumentError,
    );
  });

  test('serializes engine backend and OpenCL tuning metadata', () {
    const profile = GoEngineProfile(
      id: 'opencl',
      name: 'OpenCL GPU',
      backend: GoEngineBackend.opencl,
      openclGpuIdx: 2,
      openclLibraryName: 'libkatago-opencl.so',
      openclTuningId: 'model-gpu-2',
      openclTuningPlan: 'plan-data',
    );
    final restored = GoEngineProfile.fromJson(profile.toJson().cast());
    expect(restored.backend, GoEngineBackend.opencl);
    expect(restored.openclGpuIdx, 2);
    expect(restored.openclLibraryName, 'libkatago-opencl.so');
    expect(restored.openclTuningId, 'model-gpu-2');
    expect(restored.openclTuningPlan, 'plan-data');
  });

  test(
    'loads bundled human override ranges and selects matching profile',
    () async {
      final catalog = await GoHumanOverrideCatalog.load();
      expect(catalog.version, 2);
      expect(catalog.resolve(rank: 10, humanStyle: true).id, 'human_20k_4d');
      expect(catalog.resolve(rank: -4, humanStyle: true).id, 'human_5d_6d');
      expect(catalog.resolve(rank: 0, humanStyle: true).id, 'human_20k_4d');
      expect(catalog.resolve(rank: -3, humanStyle: true).id, 'human_20k_4d');
      expect(catalog.resolve(rank: -5, humanStyle: true).id, 'human_5d_6d');
      expect(catalog.resolve(rank: -6, humanStyle: true).id, 'human_7d_9d');
      expect(catalog.resolve(rank: -8, humanStyle: true).id, 'human_7d_9d');
      expect(catalog.resolve(rank: -9, humanStyle: true).id, 'global');
      expect(catalog.resolve(rank: -4, humanStyle: false).id, 'global');
      final config = await catalog.resolveConfig(rank: 10, humanStyle: true);
      expect(config, contains('humanSLChosenMovePiklLambda=100000000'));
    },
  );

  test('rejects incomplete and overlapping human override ranges', () {
    expect(
      () => GoHumanOverrideRule.fromJson({
        'id': 'bad',
        'displayName': 'bad',
        'rankMin': 5,
      }),
      throwsFormatException,
    );
    expect(
      () => GoHumanOverrideCatalog.fromJson({
        'version': 2,
        'normalRules': [
          {'id': 'global', 'displayName': 'All'},
        ],
        'humanRules': [
          {'id': 'a', 'displayName': 'A', 'rankMin': 10, 'rankMax': 0},
          {'id': 'b', 'displayName': 'B', 'rankMin': 5, 'rankMax': -2},
        ],
      }),
      throwsFormatException,
    );
  });

  test(
    'editing built-in config persists and reset restores the default',
    () async {
      await GoEngineLibrary.save(
        const GoEngineProfile(id: 'default', name: 'My CPU', searchThreads: 4),
      );
      expect((await GoEngineLibrary.byId('default')).searchThreads, 4);
      await GoEngineLibrary.resetBuiltIn();
      expect((await GoEngineLibrary.byId('default')).searchThreads, 2);
    },
  );

  test(
    'rejects incomplete, overlapping, duplicated and out-of-range custom rules',
    () {
      for (final rules in [
        [const GoEngineOverrideRule(id: 'a', displayName: 'a', rankMin: 20)],
        [
          const GoEngineOverrideRule(
            id: 'a',
            displayName: 'a',
            rankMin: 21,
            rankMax: 1,
          ),
        ],
        [
          const GoEngineOverrideRule(id: 'a', displayName: 'a'),
          const GoEngineOverrideRule(id: 'b', displayName: 'b'),
        ],
        [
          const GoEngineOverrideRule(
            id: 'a',
            displayName: 'a',
            rankMin: 20,
            rankMax: 1,
          ),
          const GoEngineOverrideRule(
            id: 'b',
            displayName: 'b',
            rankMin: 2,
            rankMax: -8,
          ),
        ],
      ]) {
        expect(
          () => GoEngineOverrideRule.validateList(rules),
          throwsArgumentError,
        );
      }
    },
  );
}
