// Flutter adaptation of KernelSU's Material theme page (GPL-3.0).
// Reference and upstream notices: docs/THEMES.md.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_theme.dart';
import 'theme_controller.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key, required this.controller});
  final ThemeController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final colors = controller.scheme(dark: dark, color: controller.keyColor);
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverAppBar.large(title: Text('主题设置')),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList.list(
                children: [
                  _ThemePreview(scheme: colors),
                  const SizedBox(height: 13),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      key: const ValueKey('theme-colors'),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: appKeyColors.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                        final color = index == 0
                            ? null
                            : appKeyColors[index - 1];
                        return _ColorButton(
                          label: index == 0
                              ? '默认'
                              : appKeyColorNames[index - 1],
                          selected: controller.keyColor == color,
                          scheme: controller.scheme(dark: dark, color: color),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            controller.setColor(color);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 13),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SegmentedButton<AppAppearance>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: AppAppearance.system,
                          icon: Icon(Icons.brightness_4),
                          tooltip: '跟随系统',
                        ),
                        ButtonSegment(
                          value: AppAppearance.light,
                          icon: Icon(Icons.brightness_7),
                          tooltip: '浅色',
                        ),
                        ButtonSegment(
                          value: AppAppearance.dark,
                          icon: Icon(Icons.brightness_3),
                          tooltip: '深色',
                        ),
                        ButtonSegment(
                          value: AppAppearance.amoled,
                          icon: Icon(Icons.brightness_1),
                          tooltip: 'AMOLED 纯黑',
                        ),
                      ],
                      selected: {controller.appearance},
                      onSelectionChanged: (value) {
                        HapticFeedback.selectionClick();
                        controller.setAppearance(value.single);
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(switch (controller.appearance) {
                      AppAppearance.system => '跟随系统',
                      AppAppearance.light => '浅色',
                      AppAppearance.dark => '深色',
                      AppAppearance.amoled => 'AMOLED 纯黑',
                    }),
                  ),
                  const SizedBox(height: 13),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            DropdownButtonFormField<DynamicSchemeVariant>(
                              isExpanded: true,
                              key: ValueKey(controller.paletteStyle),
                              initialValue: controller.paletteStyle,
                              decoration: const InputDecoration(
                                labelText: '色彩风格',
                                prefixIcon: Icon(Icons.style),
                              ),
                              items: [
                                for (final style in const [
                                  DynamicSchemeVariant.tonalSpot,
                                  DynamicSchemeVariant.neutral,
                                  DynamicSchemeVariant.vibrant,
                                  DynamicSchemeVariant.expressive,
                                  DynamicSchemeVariant.rainbow,
                                  DynamicSchemeVariant.fruitSalad,
                                  DynamicSchemeVariant.monochrome,
                                  DynamicSchemeVariant.fidelity,
                                  DynamicSchemeVariant.content,
                                ])
                                  DropdownMenuItem(
                                    value: style,
                                    child: Text(
                                      paletteStyleLabel(style),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) controller.setStyle(v);
                              },
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<AppColorSpec>(
                              isExpanded: true,
                              key: ValueKey(controller.colorSpec),
                              initialValue: controller.colorSpec,
                              decoration: const InputDecoration(
                                labelText: '色彩标准',
                                prefixIcon: Icon(Icons.design_services),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: AppColorSpec.spec2021,
                                  child: Text('SPEC_2021'),
                                ),
                                DropdownMenuItem(
                                  value: AppColorSpec.spec2025,
                                  child: Text('SPEC_2025'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) controller.setSpec(v);
                              },
                            ),
                            if (controller.colorSpec == AppColorSpec.spec2025 &&
                                !const [
                                  DynamicSchemeVariant.tonalSpot,
                                  DynamicSchemeVariant.neutral,
                                  DynamicSchemeVariant.vibrant,
                                  DynamicSchemeVariant.expressive,
                                ].contains(controller.paletteStyle))
                              const Padding(
                                padding: EdgeInsets.only(top: 10),
                                child: Text('此风格使用 SPEC_2021 配色'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  _PageScaleControl(controller: controller),
                  if (controller.error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(controller.error!),
                          TextButton(
                            onPressed: controller.refresh,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PageScaleControl extends StatefulWidget {
  const _PageScaleControl({required this.controller});
  final ThemeController controller;
  @override
  State<_PageScaleControl> createState() => _PageScaleControlState();
}

class _PageScaleControlState extends State<_PageScaleControl> {
  double? _dragValue;
  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.controller.pageScale;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.aspect_ratio),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text('界面缩放'), Text('调整全局显示比例')],
                    ),
                  ),
                  Text('${(value * 100).round()}%'),
                ],
              ),
              Slider(
                key: const ValueKey('theme-scale'),
                value: value,
                min: 0.8,
                max: 1.1,
                onChanged: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  widget.controller.setScale(v);
                  setState(() => _dragValue = null);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.scheme});
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(screen.width * 0.4, 240.0);
    final height = (width * screen.height / screen.width).clamp(140.0, 300.0);
    return Center(
      child: Semantics(
        label: '主题预览',
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'EasyPlay',
                  style: TextStyle(color: scheme.onSurface, fontSize: 13),
                ),
              ),
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceBright,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(child: Icon(Icons.home, color: scheme.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.label,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                padding: const EdgeInsets.all(4),
                child: CustomPaint(
                  painter: _PalettePainter(scheme),
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary,
                      ),
                      child: selected
                          ? Icon(Icons.check, color: scheme.onPrimary, size: 16)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PalettePainter extends CustomPainter {
  const _PalettePainter(this.scheme);
  final ColorScheme scheme;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      true,
      Paint()..color = scheme.primaryContainer,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi,
      true,
      Paint()..color = scheme.tertiaryContainer,
    );
  }

  @override
  bool shouldRepaint(_PalettePainter old) => old.scheme != scheme;
}

/// Scale layout as well as painting; touch positions and system insets remain
/// aligned with the logical viewport. Text-only scaling is not page scaling.
class AppPageScale extends StatelessWidget {
  const AppPageScale({super.key, required this.scale, required this.child});
  final double scale;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        final size = Size(bounds.maxWidth / scale, bounds.maxHeight / scale);
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: MediaQuery(
                  data: media.copyWith(
                    size: size,
                    padding: media.padding / scale,
                    viewPadding: media.viewPadding / scale,
                    viewInsets: media.viewInsets / scale,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
