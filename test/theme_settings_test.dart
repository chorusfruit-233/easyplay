import 'package:easyplay/app_theme.dart';
import 'package:easyplay/main.dart';
import 'package:easyplay/theme_controller.dart';
import 'package:easyplay/theme_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'old AMOLED switch migrates into a persistent forced-dark mode',
    () async {
      SharedPreferences.setMockInitialValues({
        'appearance': 'system',
        'theme_amoled': true,
      });
      final theme = ThemeController();
      await theme.load();
      expect(theme.appearance, AppAppearance.amoled);
      expect(theme.mode, ThemeMode.dark);
      expect(theme.scheme(dark: true).surface, Colors.black);
      await theme.setAppearance(AppAppearance.light);
      final restored = ThemeController();
      await restored.load();
      expect(restored.appearance, AppAppearance.light);
      theme.dispose();
      restored.dispose();
    },
  );
  test(
    'color, full palette style, standard and scale survive restart',
    () async {
      final theme = ThemeController();
      await theme.load();
      await theme.setColor(appKeyColors.last);
      await theme.setStyle(DynamicSchemeVariant.monochrome);
      await theme.setSpec(AppColorSpec.spec2021);
      await theme.setScale(0.85);
      final restored = ThemeController();
      await restored.load();
      expect(restored.keyColor, appKeyColors.last);
      expect(restored.paletteStyle, DynamicSchemeVariant.monochrome);
      expect(restored.colorSpec, AppColorSpec.spec2021);
      expect(restored.pageScale, 0.85);
      await restored.setColor(null);
      expect(
        (await SharedPreferences.getInstance()).getInt('theme_key_color'),
        0,
      );
      theme.dispose();
      restored.dispose();
    },
  );

  testWidgets('theme controls stay selected after repeated route changes', (
    tester,
  ) async {
    await tester.pumpWidget(const EasyPlayApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AMOLED 纯黑'));
    await tester.pumpAndSettle();
    final segment = tester.widget<SegmentedButton<AppAppearance>>(
      find.byType(SegmentedButton<AppAppearance>),
    );
    expect(segment.selected, {AppAppearance.amoled});
    expect(
      Theme.of(
        tester.element(find.byType(ThemeSettingsPage)),
      ).colorScheme.surfaceContainerHighest,
      Colors.black,
    );
    await tester.tap(find.byTooltip('浅色'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<AppAppearance>>(
            find.byType(SegmentedButton<AppAppearance>),
          )
          .selected,
      {AppAppearance.light},
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题设置'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<AppAppearance>>(
            find.byType(SegmentedButton<AppAppearance>),
          )
          .selected,
      {AppAppearance.light},
    );
    expect(
      (await SharedPreferences.getInstance()).getString('appearance'),
      'light',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'narrow scaled theme page supports selectors and color scrolling',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final theme = ThemeController();
      await tester.runAsync(() => theme.load());
      await theme.setScale(1.1);
      await tester.pumpWidget(
        AnimatedBuilder(
          animation: theme,
          builder: (context, _) => MaterialApp(
            theme: AppTheme.fromScheme(theme.scheme(dark: false)),
            builder: (context, child) =>
                AppPageScale(scale: theme.pageScale, child: child!),
            home: ThemeSettingsPage(controller: theme),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('theme-colors')),
        const Offset(-1600, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('樱花'));
      await tester.pumpAndSettle();
      expect(theme.keyColor, appKeyColors.last);
      final style = find.byType(DropdownButtonFormField<DynamicSchemeVariant>);
      await tester.ensureVisible(style);
      await tester.pumpAndSettle();
      await tester.tap(style);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monochrome').last);
      await tester.pumpAndSettle();
      expect(theme.paletteStyle, DynamicSchemeVariant.monochrome);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
    },
  );

  testWidgets(
    'disposing while preferences load does not notify dead listeners',
    (tester) async {
      await tester.pumpWidget(const EasyPlayApp());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
