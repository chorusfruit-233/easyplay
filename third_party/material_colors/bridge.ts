// EasyPlay adapter for Google's Apache-2.0 Material Color Utilities.
import {DynamicScheme} from './typescript/dynamiccolor/dynamic_scheme';
import {Hct} from './typescript/hct/hct';
import {Variant} from './typescript/dynamiccolor/variant';
const variants: Record<string, Variant> = {
 tonalSpot: Variant.TONAL_SPOT, neutral: Variant.NEUTRAL, vibrant: Variant.VIBRANT,
 expressive: Variant.EXPRESSIVE, monochrome: Variant.MONOCHROME, fidelity: Variant.FIDELITY,
 content: Variant.CONTENT, rainbow: Variant.RAINBOW, fruitSalad: Variant.FRUIT_SALAD,
};
export function materialColors(raw: string): string {
 const {seeds, style, spec, dark} = JSON.parse(raw);
 const version = spec === 'spec2025' && ['tonalSpot','neutral','vibrant','expressive'].includes(style) ? '2025' : '2021';
 return JSON.stringify(seeds.map((seed: number) => {
  const scheme = new DynamicScheme({sourceColorHct: Hct.fromInt(seed), variant: variants[style], isDark: dark, contrastLevel: 0, specVersion: version, platform: 'phone'});
  return {
   primary: scheme.primary >>> 0,
   onPrimary: scheme.onPrimary >>> 0,
   primaryContainer: scheme.primaryContainer >>> 0,
   onPrimaryContainer: scheme.onPrimaryContainer >>> 0,
   primaryFixed: scheme.primaryFixed >>> 0,
   primaryFixedDim: scheme.primaryFixedDim >>> 0,
   onPrimaryFixed: scheme.onPrimaryFixed >>> 0,
   onPrimaryFixedVariant: scheme.onPrimaryFixedVariant >>> 0,
   secondary: scheme.secondary >>> 0,
   onSecondary: scheme.onSecondary >>> 0,
   secondaryContainer: scheme.secondaryContainer >>> 0,
   onSecondaryContainer: scheme.onSecondaryContainer >>> 0,
   secondaryFixed: scheme.secondaryFixed >>> 0,
   secondaryFixedDim: scheme.secondaryFixedDim >>> 0,
   onSecondaryFixed: scheme.onSecondaryFixed >>> 0,
   onSecondaryFixedVariant: scheme.onSecondaryFixedVariant >>> 0,
   tertiary: scheme.tertiary >>> 0,
   onTertiary: scheme.onTertiary >>> 0,
   tertiaryContainer: scheme.tertiaryContainer >>> 0,
   onTertiaryContainer: scheme.onTertiaryContainer >>> 0,
   tertiaryFixed: scheme.tertiaryFixed >>> 0,
   tertiaryFixedDim: scheme.tertiaryFixedDim >>> 0,
   onTertiaryFixed: scheme.onTertiaryFixed >>> 0,
   onTertiaryFixedVariant: scheme.onTertiaryFixedVariant >>> 0,
   error: scheme.error >>> 0,
   onError: scheme.onError >>> 0,
   errorContainer: scheme.errorContainer >>> 0,
   onErrorContainer: scheme.onErrorContainer >>> 0,
   surface: scheme.surface >>> 0,
   onSurface: scheme.onSurface >>> 0,
   surfaceDim: scheme.surfaceDim >>> 0,
   surfaceBright: scheme.surfaceBright >>> 0,
   surfaceContainerLowest: scheme.surfaceContainerLowest >>> 0,
   surfaceContainerLow: scheme.surfaceContainerLow >>> 0,
   surfaceContainer: scheme.surfaceContainer >>> 0,
   surfaceContainerHigh: scheme.surfaceContainerHigh >>> 0,
   surfaceContainerHighest: scheme.surfaceContainerHighest >>> 0,
   onSurfaceVariant: scheme.onSurfaceVariant >>> 0,
   outline: scheme.outline >>> 0,
   outlineVariant: scheme.outlineVariant >>> 0,
   shadow: scheme.shadow >>> 0,
   scrim: scheme.scrim >>> 0,
   inverseSurface: scheme.inverseSurface >>> 0,
   onInverseSurface: scheme.inverseOnSurface >>> 0,
   inversePrimary: scheme.inversePrimary >>> 0,
   surfaceTint: scheme.surfaceTint >>> 0,
  };
 }));
}
(globalThis as any).easyplayMaterialColors = materialColors;
