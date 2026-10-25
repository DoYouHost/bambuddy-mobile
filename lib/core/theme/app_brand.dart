import 'package:material_ui/material_ui.dart';

import '../settings/appearance_prefs.dart';
import 'appearance_providers.dart' show SystemSchemes;
import 'dash_theme.dart';

/// The brand an accent choice paints with.
///
/// `system` falls back to [bambuddyBrand] while there are no system schemes
/// (below Android 12, or a device without a palette), so a stored choice can
/// never leave the app without an accent.
DashBrand resolveBrand(AccentSource accent, SystemSchemes? system) =>
    switch (accent) {
      AccentSource.bambuddy => bambuddyBrand,
      AccentSource.system =>
        system == null
            ? bambuddyBrand
            : DashBrand.fromSchemes(light: system.light, dark: system.dark),
      _ => _fromPreset(accentPresets[accent]!),
    };

/// A preset's seed and the Material scheme variant it is generated with.
typedef AccentPreset = ({Color seed, DynamicSchemeVariant variant});

const accentPresets = <AccentSource, AccentPreset>{
  AccentSource.blue: (
    seed: Color(0xFF2E7DD7),
    variant: DynamicSchemeVariant.tonalSpot,
  ),
  AccentSource.purple: (
    seed: Color(0xFF7E57C2),
    variant: DynamicSchemeVariant.tonalSpot,
  ),
  AccentSource.orange: (
    seed: Color(0xFFF57C00),
    variant: DynamicSchemeVariant.tonalSpot,
  ),
  AccentSource.pink: (
    seed: Color(0xFFD81B60),
    variant: DynamicSchemeVariant.tonalSpot,
  ),
  // tonalSpot lifts any seed to a chroma of about 36, so a grey seed would come
  // out coloured; monochrome keeps it grey.
  AccentSource.graphite: (
    seed: Color(0xFF607D8B),
    variant: DynamicSchemeVariant.monochrome,
  ),
};

DashBrand _fromPreset(AccentPreset preset) {
  ColorScheme scheme(Brightness brightness) => ColorScheme.fromSeed(
    seedColor: preset.seed,
    brightness: brightness,
    dynamicSchemeVariant: preset.variant,
  );
  return DashBrand.fromSchemes(
    light: scheme(Brightness.light),
    dark: scheme(Brightness.dark),
  );
}

/// What the watch is told to colour itself with: null for the green brand, which
/// the watch already draws without being told, and for a "System" with no
/// palette behind it. `System` sends the seed `toColorScheme` derives the
/// phone's scheme from, so the watch lands on the same hue.
AccentPreset? watchAccent(AccentSource accent, SystemSchemes? system) =>
    switch (accent) {
      AccentSource.bambuddy => null,
      AccentSource.system =>
        system == null
            ? null
            : (
                seed: system.light.primary,
                variant: DynamicSchemeVariant.tonalSpot,
              ),
      _ => accentPresets[accent],
    };
