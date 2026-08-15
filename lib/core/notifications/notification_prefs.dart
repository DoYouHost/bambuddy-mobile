import 'dart:convert';

/// Local notification types that [PrintMonitor] can detect from WS `printer_status` frames.
/// Intentionally omits queue events and bambuddy server features (quiet hours, digests, providers) —
/// only includes what can be inferred locally from printer status.
enum NotifEvent {
  printStarted,
  printFinished,
  printFailed,
  firstLayer,
  milestones,
  plateNotEmpty,
  printerOffline,
  printerError,
  lowFilament,
  amsHumidity,
  bedCooled,

  /// Maintenance task became overdue (`is_due`). Source: REST `/maintenance/overview`
  /// (NOT WS frames) — checked periodically in background.
  maintenanceDue,
}

/// User's notification preferences: which events trigger notifications and with what thresholds.
/// Serialized to a SINGLE JSON string in SharedPreferences so the background isolate
/// (which reads `SharedPreferences.getInstance()` from scratch) can parse it the same way as the UI.
/// Parsing is lenient — unknown event names are skipped (forward compatibility:
/// older app won't crash on new enum values).
class NotificationPrefs {
  const NotificationPrefs({
    required this.enabled,
    this.alertsEnabled = true,
    this.finishPhoto = true,
    this.bedCooledTemp = defaultBedCooledTemp,
    this.amsHumidityThreshold = defaultAmsHumidity,
    this.lowFilamentThreshold = defaultLowFilament,
  });

  /// Master switch for all event alerts. When false, [isOn] returns false for
  /// every event, silencing all alerts (start/finish/error/maintenance/…) while
  /// leaving the ongoing print-progress notification untouched (it never calls
  /// [isOn]). Per-event choices below are preserved and restored when re-enabled.
  final bool alertsEnabled;

  /// Set of events for which we send notifications.
  final Set<NotifEvent> enabled;

  /// Whether the photo the server takes when a print ends is added to the
  /// finished/failed alert once it arrives. Not an event of its own — it only
  /// decorates an alert those two switches already allowed — so it lives here
  /// rather than in [enabled], and the download it costs is opt-out for anyone
  /// watching their data.
  final bool finishPhoto;

  /// Threshold for "bed cooled": alert when bed temperature falls below (°C).
  final int bedCooledTemp;

  /// Threshold for "high AMS humidity": alert when humidity exceeds (%).
  final int amsHumidityThreshold;

  /// Threshold for "low filament": alert when remaining amount falls below (%).
  final int lowFilamentThreshold;

  static const int defaultBedCooledTemp = 35;
  static const int defaultAmsHumidity = 60;
  static const int defaultLowFilament = 10;

  /// By default, only "actionable" events are enabled; the rest are silent (OFF)
  /// to avoid overwhelming the user — they can enable them in settings.
  static const Set<NotifEvent> _defaultEnabled = {
    NotifEvent.printFinished,
    NotifEvent.printFailed,
    NotifEvent.plateNotEmpty,
    NotifEvent.printerError,
    NotifEvent.maintenanceDue,
  };

  static const NotificationPrefs defaults =
      NotificationPrefs(enabled: _defaultEnabled);

  bool isOn(NotifEvent e) => alertsEnabled && enabled.contains(e);

  NotificationPrefs copyWith({
    bool? alertsEnabled,
    bool? finishPhoto,
    Set<NotifEvent>? enabled,
    int? bedCooledTemp,
    int? amsHumidityThreshold,
    int? lowFilamentThreshold,
  }) =>
      NotificationPrefs(
        alertsEnabled: alertsEnabled ?? this.alertsEnabled,
        finishPhoto: finishPhoto ?? this.finishPhoto,
        enabled: enabled ?? this.enabled,
        bedCooledTemp: bedCooledTemp ?? this.bedCooledTemp,
        amsHumidityThreshold: amsHumidityThreshold ?? this.amsHumidityThreshold,
        lowFilamentThreshold: lowFilamentThreshold ?? this.lowFilamentThreshold,
      );

  /// Toggles a single event and returns a new object.
  NotificationPrefs withEvent(NotifEvent e, bool on) {
    final next = {...enabled};
    if (on) {
      next.add(e);
    } else {
      next.remove(e);
    }
    return copyWith(enabled: next);
  }

  Map<String, dynamic> toJson() => {
        'alertsEnabled': alertsEnabled,
        'finishPhoto': finishPhoto,
        'enabled': [for (final e in enabled) e.name],
        'bedCooledTemp': bedCooledTemp,
        'amsHumidityThreshold': amsHumidityThreshold,
        'lowFilamentThreshold': lowFilamentThreshold,
      };

  String encode() => jsonEncode(toJson());

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) {
    final rawEnabled = json['enabled'];
    final names = rawEnabled is List
        ? rawEnabled.map((e) => e.toString()).toSet()
        : const <String>{};
    final enabled = {
      for (final e in NotifEvent.values)
        if (names.contains(e.name)) e,
    };
    return NotificationPrefs(
      // Missing key (prefs saved before this flag existed) → alerts stay on.
      alertsEnabled: json['alertsEnabled'] is bool ? json['alertsEnabled'] as bool : true,
      // Same rule for the finish photo: an install that predates it gets the
      // feature rather than a silently disabled one.
      finishPhoto: json['finishPhoto'] is bool ? json['finishPhoto'] as bool : true,
      enabled: enabled,
      bedCooledTemp: _asInt(json['bedCooledTemp'], defaultBedCooledTemp),
      amsHumidityThreshold:
          _asInt(json['amsHumidityThreshold'], defaultAmsHumidity),
      lowFilamentThreshold:
          _asInt(json['lowFilamentThreshold'], defaultLowFilament),
    );
  }

  /// Decodes from a raw SharedPreferences string; corrupted/empty → defaults.
  factory NotificationPrefs.decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      return NotificationPrefs.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return defaults;
    }
  }

  static int _asInt(dynamic v, int fallback) => switch (v) {
        num n => n.toInt(),
        String s => int.tryParse(s) ?? fallback,
        _ => fallback,
      };
}
