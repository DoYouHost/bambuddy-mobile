import 'package:material_ui/material_ui.dart' show ThemeMode;

import '../models/json_utils.dart';
import '../models/value_equality.dart';

/// Where the accent comes from. Wire values are the enum names.
enum AccentSource { bambuddy, system, blue, purple, orange, pink, graphite }

/// The app's colour and light/dark choice, kept per device. One JSON object,
/// so a damaged field costs that field and nothing else.
class AppearancePrefs with ValueEquality {
  const AppearancePrefs({
    this.accent = AccentSource.bambuddy,
    this.mode = ThemeMode.system,
  });

  final AccentSource accent;
  final ThemeMode mode;

  AppearancePrefs copyWith({AccentSource? accent, ThemeMode? mode}) =>
      AppearancePrefs(accent: accent ?? this.accent, mode: mode ?? this.mode);

  /// Missing, unknown or mistyped fields read as today's look: the green
  /// accent following the system's light/dark setting.
  factory AppearancePrefs.fromJson(Map<String, dynamic> json) =>
      AppearancePrefs(
        accent:
            enumByName(AccentSource.values, json['accent']) ??
            AccentSource.bambuddy,
        mode: enumByName(ThemeMode.values, json['mode']) ?? ThemeMode.system,
      );

  Map<String, dynamic> toJson() => {'accent': accent.name, 'mode': mode.name};

  @override
  List<Object?> get props => [accent, mode];
}

/// Where a paired watch takes its colours from: its face, this phone's
/// accent, or [WatchAppearance.preset].
enum WatchThemeSource { face, phone, preset }

/// The watch's colours, chosen on the phone. Same tolerant JSON as
/// [AppearancePrefs]: anything unreadable is the default, the phone's accent.
class WatchAppearance with ValueEquality {
  const WatchAppearance({
    this.source = WatchThemeSource.phone,
    this.preset = AccentSource.bambuddy,
  });

  final WatchThemeSource source;

  /// Used while [source] is [WatchThemeSource.preset]; never `system`.
  final AccentSource preset;

  WatchAppearance copyWith({WatchThemeSource? source, AccentSource? preset}) =>
      WatchAppearance(
        source: source ?? this.source,
        preset: preset ?? this.preset,
      );

  factory WatchAppearance.fromJson(Map<String, dynamic> json) {
    final preset = enumByName(AccentSource.values, json['preset']);
    return WatchAppearance(
      source:
          enumByName(WatchThemeSource.values, json['source']) ??
          WatchThemeSource.phone,
      preset: preset == null || preset == AccentSource.system
          ? AccentSource.bambuddy
          : preset,
    );
  }

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'preset': preset.name,
  };

  @override
  List<Object?> get props => [source, preset];
}
