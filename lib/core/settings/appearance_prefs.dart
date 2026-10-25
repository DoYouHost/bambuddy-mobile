import 'package:flutter/material.dart' show ThemeMode;

/// Where the accent comes from. Wire values are the enum names.
enum AccentSource { bambuddy, system, blue, purple, orange, pink, graphite }

/// The app's colour and light/dark choice, kept per device. One JSON object,
/// so a damaged field costs that field and nothing else.
class AppearancePrefs {
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
            _byName(AccentSource.values, json['accent']) ??
            AccentSource.bambuddy,
        mode: _byName(ThemeMode.values, json['mode']) ?? ThemeMode.system,
      );

  Map<String, dynamic> toJson() => {'accent': accent.name, 'mode': mode.name};

  @override
  bool operator ==(Object other) =>
      other is AppearancePrefs && other.accent == accent && other.mode == mode;

  @override
  int get hashCode => Object.hash(accent, mode);
}

T? _byName<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull;
