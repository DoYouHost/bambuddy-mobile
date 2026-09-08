import 'json_utils.dart';
import '../settings/server_settings.dart';

/// One editable server setting: where it lives on the wire, and what the server
/// accepts. Bounds are `schemas/settings.py::AppSettingsUpdate`'s own, which
/// answers **422** rather than clamping.
enum QueueSetting {
  requirePlateClear('require_plate_clear'),
  shortestFirst('queue_shortest_first'),
  maxConcurrentUploads('queue_max_concurrent_uploads', min: 1, max: 16),
  preheatEnabled('preheat_enabled'),
  preheatMaxWaitSeconds('preheat_max_wait_seconds', min: 60, max: 3600),
  preheatSoakSeconds('preheat_soak_seconds', min: 0, max: 1800),
  keepBedWarm('queue_keep_bed_warm'),
  keepWarmBedTemp('queue_keep_warm_bed_temp', min: 40, max: 110),
  keepWarmMaxMinutes('queue_keep_warm_max_minutes', min: 5, max: 480);

  const QueueSetting(this.key, {this.min, this.max});

  final String key;

  /// Null on the flags, which have no range of their own.
  final int? min;
  final int? max;

  /// `AppSettings`' own field default. Only reached when the server answered
  /// the key with something unreadable — an absent key means no such setting.
  int get serverDefault => switch (this) {
    maxConcurrentUploads => 4,
    preheatMaxWaitSeconds => 900,
    preheatSoakSeconds => 300,
    keepWarmBedTemp => 90,
    keepWarmMaxMinutes => 120,
    _ => 0,
  };
}

/// The queue / preheat / keep-warm block of the server's `AppSettings`, plus
/// what the map alone cannot say: **which of these keys the server knows**.
///
/// `GET /settings` serializes every field the schema has, defaulted, so a
/// missing key means the server predates the setting. Writing one is not
/// refused but silently dropped (`extra="ignore"`), which is why a row nobody
/// answered for must never be offered.
class QueueSettings {
  const QueueSettings({required this.values, required this.known});

  /// A key the server did not send is absent from both maps rather than
  /// defaulted into [values] — "off" and "no such setting" must stay apart.
  factory QueueSettings.fromSettings(Map<String, dynamic> settings) {
    final values = <QueueSetting, Object>{};
    final known = <QueueSetting>{};
    for (final setting in QueueSetting.values) {
      if (!settings.containsKey(setting.key)) continue;
      known.add(setting);
      values[setting] = setting.min == null
          ? settings.settingBool(setting.key)
          : toIntOrNull(settings[setting.key]) ?? setting.serverDefault;
    }
    return QueueSettings(values: values, known: known);
  }

  final Map<QueueSetting, Object> values;

  final Set<QueueSetting> known;

  bool flag(QueueSetting setting) => values[setting] as bool? ?? false;

  int number(QueueSetting setting) =>
      values[setting] as int? ?? setting.serverDefault;

  /// This block with one setting changed, for the optimistic redraw. A setting
  /// the server does not know is a no-op, never an addition.
  QueueSettings withValue(QueueSetting setting, Object value) =>
      known.contains(setting)
      ? QueueSettings(values: {...values, setting: value}, known: known)
      : this;

  /// The `PUT /settings/` body for one change. Numbers are clamped here, the
  /// last place that knows the range before the request leaves.
  static Map<String, dynamic> patch(QueueSetting setting, Object value) => {
    setting.key: value is int
        ? value.clamp(setting.min ?? value, setting.max ?? value)
        : value,
  };
}
