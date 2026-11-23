import 'package:app_util/app_util.dart';

import '../settings/server_settings.dart';

/// How a [QueueSetting] is read, drawn and written.
enum QueueSettingKind { flag, number, choice }

/// One editable server setting: where it lives on the wire, and what the server
/// accepts. Bounds are `schemas/settings.py::AppSettingsUpdate`'s own, which
/// answers **422** rather than clamping.
enum QueueSetting {
  requirePlateClear('require_plate_clear'),
  shortestFirst('queue_shortest_first'),
  maxConcurrentUploads.number('queue_max_concurrent_uploads', min: 1, max: 16),
  preheatEnabled('preheat_enabled'),
  preheatMaxWaitSeconds.number('preheat_max_wait_seconds', min: 60, max: 3600),
  preheatSoakSeconds.number('preheat_soak_seconds', min: 0, max: 1800),
  keepBedWarm('queue_keep_bed_warm'),
  keepWarmBedTemp.number('queue_keep_warm_bed_temp', min: 40, max: 110),
  keepWarmMaxMinutes.number('queue_keep_warm_max_minutes', min: 5, max: 480),
  // Post-print outcome confirmation (#1898), Settings → Workflow on the web.
  confirmOutcomeDefault('default_confirm_outcome'),
  confirmOutcomeExternal('confirm_outcome_external_prints'),
  confirmGoodOnPlateClear('confirm_default_good_on_plate_clear'),
  // Not a queue setting: how long before a slicer pause the server and this app
  // warn (#2984). It rides on this block's writer, gate and lock — the same
  // `PUT /settings/`, key-presence gate and denied-to-API-keys rule.
  pauseWarningMinutes.number('pause_warning_minutes', min: 1, max: 120),
  // Which printer an "Any model" job takes (#2915), a [ModelDispatchOrder]. The
  // one setting here that is neither a flag nor a number.
  dispatchOrder.choice('model_dispatch_order');

  /// A switch.
  const QueueSetting(this.key)
    : kind = QueueSettingKind.flag,
      min = null,
      max = null;

  /// A whole number the server bounds and answers 422 outside of.
  const QueueSetting.number(
    this.key, {
    required int this.min,
    required int this.max,
  }) : kind = QueueSettingKind.number;

  /// One of a fixed set of strings, read through its own enum.
  const QueueSetting.choice(this.key)
    : kind = QueueSettingKind.choice,
      min = null,
      max = null;

  final String key;
  final QueueSettingKind kind;

  /// Only on a [QueueSettingKind.number].
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
    pauseWarningMinutes => 5,
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
      values[setting] = switch (setting.kind) {
        QueueSettingKind.flag => settings.settingBool(setting.key),
        QueueSettingKind.number =>
          toIntOrNull(settings[setting.key]) ?? setting.serverDefault,
        QueueSettingKind.choice => ModelDispatchOrder.fromWire(
          settings[setting.key],
        ),
      };
    }
    return QueueSettings(values: values, known: known);
  }

  final Map<QueueSetting, Object> values;

  final Set<QueueSetting> known;

  bool flag(QueueSetting setting) => values[setting] as bool? ?? false;

  int number(QueueSetting setting) =>
      values[setting] as int? ?? setting.serverDefault;

  ModelDispatchOrder get dispatchOrder =>
      values[QueueSetting.dispatchOrder] as ModelDispatchOrder? ??
      ModelDispatchOrder.fewestHours;

  /// This block with one setting changed, for the optimistic redraw. A setting
  /// the server does not know is a no-op, never an addition.
  QueueSettings withValue(QueueSetting setting, Object value) =>
      known.contains(setting)
      ? QueueSettings(values: {...values, setting: value}, known: known)
      : this;

  /// The `PUT /settings/` body for one change. Numbers are clamped here, the
  /// last place that knows the range before the request leaves.
  static Map<String, dynamic> patch(QueueSetting setting, Object value) => {
    setting.key: switch (value) {
      int() => value.clamp(setting.min ?? value, setting.max ?? value),
      ModelDispatchOrder() => value.wire,
      _ => value,
    },
  };
}

/// How an "Any model" job picks among the printers that can take it
/// (`schemas/settings.py::AppSettingsUpdate.model_dispatch_order`, a `Literal`
/// that answers **422** to anything else).
enum ModelDispatchOrder {
  fewestHours('fewest_hours'),
  mostHours('most_hours'),
  leastRecentlyUsed('least_recently_used'),

  /// Follows each printer's own `dispatch_priority`.
  priority('priority');

  const ModelDispatchOrder(this.wire);

  final String wire;

  /// What the scheduler does with a stored value it does not know: it reads it
  /// as the default (`print_scheduler.py::_get_model_dispatch_order`), so a
  /// later server's fifth order shows here as the default rather than breaking
  /// the screen.
  static ModelDispatchOrder fromWire(Object? value) => values.firstWhere(
    (order) => order.wire == value,
    orElse: () => fewestHours,
  );
}
