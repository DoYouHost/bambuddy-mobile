import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme/app_brand.dart' show AccentPreset;
import '../core/theme/appearance_providers.dart';
import '../providers.dart';
import 'wear_theme.dart';

const _channel = MethodChannel(
  'page.codeberg.morganmlgman.bambuddy/watch_face_colours',
);

/// The watch face's colours, or null where Wear OS gives none (below Android
/// 15, or dynamic theming switched off). Never throws, like `readSystemSchemes`.
///
/// Returned as both halves of [SystemSchemes] so the phone's re-read on resume
/// (`systemSchemesProvider`) carries it unchanged; the watch draws only dark.
/// Not `dynamic_color`: on a watch the system palette it reads answers even
/// with dynamic theming off, with defaults unrelated to the face.
Future<SystemSchemes?> readWatchFaceSchemes() async {
  try {
    final roles = await _channel.invokeMapMethod<String, int>('roles');
    if (roles == null) return null;
    final scheme = watchFaceScheme(roles);
    return (light: scheme, dark: scheme);
  } on Object {
    return null;
  }
}

/// [roles] as `WatchFaceColours.kt` names them, on the black the watch draws on
/// (WO-V13). Throws on a missing role, which [readWatchFaceSchemes] reads as no
/// palette.
ColorScheme watchFaceScheme(Map<String, int> roles) {
  Color role(String name) => Color(roles[name]!);
  return ColorScheme(
    brightness: Brightness.dark,
    primary: role('primary'),
    onPrimary: role('onPrimary'),
    primaryContainer: role('primaryContainer'),
    onPrimaryContainer: role('onPrimaryContainer'),
    secondary: role('secondary'),
    onSecondary: role('onSecondary'),
    secondaryContainer: role('secondaryContainer'),
    onSecondaryContainer: role('onSecondaryContainer'),
    tertiary: role('tertiary'),
    onTertiary: role('onTertiary'),
    tertiaryContainer: role('tertiaryContainer'),
    onTertiaryContainer: role('onTertiaryContainer'),
    error: role('error'),
    onError: role('onError'),
    errorContainer: role('errorContainer'),
    onErrorContainer: role('onErrorContainer'),
    surface: Colors.black,
    onSurface: role('onSurface'),
    onSurfaceVariant: role('onSurfaceVariant'),
    outline: role('outline'),
    outlineVariant: role('outlineVariant'),
    surfaceContainerLow: role('surfaceContainerLow'),
    surfaceContainer: role('surfaceContainer'),
    surfaceContainerHigh: role('surfaceContainerHigh'),
  );
}

/// Whether the phone chose the watch face's colours (`watchFace` in the
/// config); off, the accent it sent.
final wearFaceColoursProvider = NotifierProvider<WearFaceColours, bool>(
  WearFaceColours.new,
);

class WearFaceColours extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).loadWearFaceColours();

  Future<void> set(bool value) async {
    if (value == state) return;
    state = value;
    final settings = ref.read(settingsRepositoryProvider);
    try {
      await settings.saveWearFaceColours(value);
    } catch (_) {
      state = settings.loadWearFaceColours();
      rethrow;
    }
  }
}

/// The accent the phone last sent — its own or a preset chosen for the
/// watch; null is the green brand.
final wearPhoneAccentProvider =
    NotifierProvider<WearPhoneAccent, AccentPreset?>(WearPhoneAccent.new);

class WearPhoneAccent extends Notifier<AccentPreset?> {
  @override
  AccentPreset? build() =>
      ref.watch(settingsRepositoryProvider).loadWearPhoneAccent();

  Future<void> set(AccentPreset? accent) async {
    if (accent == state) return;
    state = accent;
    final settings = ref.read(settingsRepositoryProvider);
    try {
      await settings.saveWearPhoneAccent(accent);
    } catch (_) {
      state = settings.loadWearPhoneAccent();
      rethrow;
    }
  }
}

/// The face's colours when chosen and on offer, otherwise the accent the
/// phone sent, otherwise green.
ColorScheme wearColorScheme({
  required bool faceColours,
  ColorScheme? face,
  AccentPreset? accent,
}) => (faceColours ? face : null) ?? wearSeedScheme(accent ?? wearGreen);

final wearColorSchemeProvider = Provider<ColorScheme>(
  (ref) => wearColorScheme(
    faceColours: ref.watch(wearFaceColoursProvider),
    face: ref.watch(systemSchemesProvider)?.dark,
    accent: ref.watch(wearPhoneAccentProvider),
  ),
);
