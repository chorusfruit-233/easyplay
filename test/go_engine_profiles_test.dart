import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyplay/go_engine_profiles.dart';

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
}
