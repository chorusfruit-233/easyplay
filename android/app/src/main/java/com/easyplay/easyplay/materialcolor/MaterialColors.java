package com.easyplay.easyplay.materialcolor;

import com.easyplay.easyplay.materialcolor.dynamiccolor.*;
import com.easyplay.easyplay.materialcolor.hct.Hct;
import java.util.*;

/** EasyPlay bridge; upstream algorithms retain their Apache-2.0 notices. */
public final class MaterialColors {
  public static List<Map<String, Long>> generate(List<Number> seeds, String style, String specName, boolean dark) {
    Variant variant = Variant.valueOf(style.replaceAll("([a-z])([A-Z])", "$1_$2").toUpperCase(Locale.ROOT));
    boolean modern = specName.equals("spec2025") && Arrays.asList("tonalSpot", "neutral", "vibrant", "expressive").contains(style);
    ColorSpec.SpecVersion version = modern ? ColorSpec.SpecVersion.SPEC_2025 : ColorSpec.SpecVersion.SPEC_2021;
    ColorSpec spec = ColorSpecs.get(version);
    DynamicScheme.Platform platform = DynamicScheme.Platform.PHONE;
    List<Map<String, Long>> result = new ArrayList<>();
    for (Number seed : seeds) {
      Hct hct = Hct.fromInt(seed.intValue());
      DynamicScheme scheme = new DynamicScheme(hct, variant, dark, 0.0, platform, version,
          spec.getPrimaryPalette(variant, hct, dark, platform, 0.0),
          spec.getSecondaryPalette(variant, hct, dark, platform, 0.0),
          spec.getTertiaryPalette(variant, hct, dark, platform, 0.0),
          spec.getNeutralPalette(variant, hct, dark, platform, 0.0),
          spec.getNeutralVariantPalette(variant, hct, dark, platform, 0.0),
          spec.getErrorPalette(variant, hct, dark, platform, 0.0));
      Map<String, Long> row = new HashMap<>();
      row.put("primary", ((long) scheme.getPrimary()) & 0xffffffffL);
      row.put("onPrimary", ((long) scheme.getOnPrimary()) & 0xffffffffL);
      row.put("primaryContainer", ((long) scheme.getPrimaryContainer()) & 0xffffffffL);
      row.put("onPrimaryContainer", ((long) scheme.getOnPrimaryContainer()) & 0xffffffffL);
      row.put("primaryFixed", ((long) scheme.getPrimaryFixed()) & 0xffffffffL);
      row.put("primaryFixedDim", ((long) scheme.getPrimaryFixedDim()) & 0xffffffffL);
      row.put("onPrimaryFixed", ((long) scheme.getOnPrimaryFixed()) & 0xffffffffL);
      row.put("onPrimaryFixedVariant", ((long) scheme.getOnPrimaryFixedVariant()) & 0xffffffffL);
      row.put("secondary", ((long) scheme.getSecondary()) & 0xffffffffL);
      row.put("onSecondary", ((long) scheme.getOnSecondary()) & 0xffffffffL);
      row.put("secondaryContainer", ((long) scheme.getSecondaryContainer()) & 0xffffffffL);
      row.put("onSecondaryContainer", ((long) scheme.getOnSecondaryContainer()) & 0xffffffffL);
      row.put("secondaryFixed", ((long) scheme.getSecondaryFixed()) & 0xffffffffL);
      row.put("secondaryFixedDim", ((long) scheme.getSecondaryFixedDim()) & 0xffffffffL);
      row.put("onSecondaryFixed", ((long) scheme.getOnSecondaryFixed()) & 0xffffffffL);
      row.put("onSecondaryFixedVariant", ((long) scheme.getOnSecondaryFixedVariant()) & 0xffffffffL);
      row.put("tertiary", ((long) scheme.getTertiary()) & 0xffffffffL);
      row.put("onTertiary", ((long) scheme.getOnTertiary()) & 0xffffffffL);
      row.put("tertiaryContainer", ((long) scheme.getTertiaryContainer()) & 0xffffffffL);
      row.put("onTertiaryContainer", ((long) scheme.getOnTertiaryContainer()) & 0xffffffffL);
      row.put("tertiaryFixed", ((long) scheme.getTertiaryFixed()) & 0xffffffffL);
      row.put("tertiaryFixedDim", ((long) scheme.getTertiaryFixedDim()) & 0xffffffffL);
      row.put("onTertiaryFixed", ((long) scheme.getOnTertiaryFixed()) & 0xffffffffL);
      row.put("onTertiaryFixedVariant", ((long) scheme.getOnTertiaryFixedVariant()) & 0xffffffffL);
      row.put("error", ((long) scheme.getError()) & 0xffffffffL);
      row.put("onError", ((long) scheme.getOnError()) & 0xffffffffL);
      row.put("errorContainer", ((long) scheme.getErrorContainer()) & 0xffffffffL);
      row.put("onErrorContainer", ((long) scheme.getOnErrorContainer()) & 0xffffffffL);
      row.put("surface", ((long) scheme.getSurface()) & 0xffffffffL);
      row.put("onSurface", ((long) scheme.getOnSurface()) & 0xffffffffL);
      row.put("surfaceDim", ((long) scheme.getSurfaceDim()) & 0xffffffffL);
      row.put("surfaceBright", ((long) scheme.getSurfaceBright()) & 0xffffffffL);
      row.put("surfaceContainerLowest", ((long) scheme.getSurfaceContainerLowest()) & 0xffffffffL);
      row.put("surfaceContainerLow", ((long) scheme.getSurfaceContainerLow()) & 0xffffffffL);
      row.put("surfaceContainer", ((long) scheme.getSurfaceContainer()) & 0xffffffffL);
      row.put("surfaceContainerHigh", ((long) scheme.getSurfaceContainerHigh()) & 0xffffffffL);
      row.put("surfaceContainerHighest", ((long) scheme.getSurfaceContainerHighest()) & 0xffffffffL);
      row.put("onSurfaceVariant", ((long) scheme.getOnSurfaceVariant()) & 0xffffffffL);
      row.put("outline", ((long) scheme.getOutline()) & 0xffffffffL);
      row.put("outlineVariant", ((long) scheme.getOutlineVariant()) & 0xffffffffL);
      row.put("shadow", ((long) scheme.getShadow()) & 0xffffffffL);
      row.put("scrim", ((long) scheme.getScrim()) & 0xffffffffL);
      row.put("inverseSurface", ((long) scheme.getInverseSurface()) & 0xffffffffL);
      row.put("onInverseSurface", ((long) scheme.getInverseOnSurface()) & 0xffffffffL);
      row.put("inversePrimary", ((long) scheme.getInversePrimary()) & 0xffffffffL);
      row.put("surfaceTint", ((long) scheme.getSurfaceTint()) & 0xffffffffL);
      result.add(row);
    }
    return result;
  }
}
