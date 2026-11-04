/// What can ring the alarm (#61). Wire names are the stored values.
enum AlarmEvent {
  printFinished,

  /// A fault that stops or pauses the print until somebody acts, or a print
  /// that ended as failed.
  printBlocked,

  /// An AMS drying cycle ran to its end.
  dryingFinished,
}

/// Which exclusion silenced the alarm for a printer.
enum AlarmExclusion { printer, location }

/// The alarm: a full-screen, looping ring over the lock screen for the events
/// worth waking up for. Nested in `NotificationPrefs` under `alarm`.
class AlarmPrefs {
  const AlarmPrefs({
    this.enabled = false,
    this.events = const {...AlarmEvent.values},
    this.windowEnabled = true,
    this.windowStart = defaultWindowStart,
    this.windowEnd = defaultWindowEnd,
    this.ringMinutes = defaultRingMinutes,
    this.excludedPrinters = const {},
    this.excludedLocations = const {},
  });

  /// Off until asked for: it is loud, and it needs a permission the user has to
  /// grant by hand.
  final bool enabled;

  final Set<AlarmEvent> events;

  /// Whether the alarm only rings between [windowStart] and [windowEnd]; off
  /// means at any hour.
  final bool windowEnabled;

  /// Minutes after local midnight. A window whose start is later than its end
  /// spans midnight; equal ends cover the whole day.
  final int windowStart;
  final int windowEnd;

  /// How long it rings before stopping on its own; one of [ringMinuteSteps].
  final int ringMinutes;

  /// Printers the alarm never rings for, by id.
  final Set<int> excludedPrinters;

  /// Locations the alarm never rings for, by name: a printer's location is the
  /// free-text `Printer.location`, which the server also matches by name.
  final Set<String> excludedLocations;

  static const int defaultWindowStart = 22 * 60;
  static const int defaultWindowEnd = 7 * 60;
  static const int defaultRingMinutes = 10;

  /// The slider's stops. Not linear: the difference between one and two minutes
  /// matters, between 25 and 30 it does not.
  static const List<int> ringMinuteSteps = [1, 2, 3, 5, 10, 15, 20, 30];

  static const AlarmPrefs defaults = AlarmPrefs();

  bool wants(AlarmEvent e) => enabled && events.contains(e);

  /// Why the alarm stays silent for this printer, or null when it may ring.
  /// [location] null — unknown, or no location — never excludes: a missing
  /// answer rings rather than sleeps through a print.
  AlarmExclusion? exclusionOf(int printerId, String? location) {
    if (excludedPrinters.contains(printerId)) return AlarmExclusion.printer;
    if (location != null && excludedLocations.contains(location)) {
      return AlarmExclusion.location;
    }
    return null;
  }

  /// Whether [now] (local time) falls inside the window. Start inclusive, end
  /// exclusive: 22:00–07:00 rings at 22:00 and not at 07:00.
  bool inWindow(DateTime now) {
    if (!windowEnabled || windowStart == windowEnd) return true;
    final m = now.hour * 60 + now.minute;
    return windowStart < windowEnd
        ? m >= windowStart && m < windowEnd
        : m >= windowStart || m < windowEnd;
  }

  AlarmPrefs copyWith({
    bool? enabled,
    Set<AlarmEvent>? events,
    bool? windowEnabled,
    int? windowStart,
    int? windowEnd,
    int? ringMinutes,
    Set<int>? excludedPrinters,
    Set<String>? excludedLocations,
  }) => AlarmPrefs(
    enabled: enabled ?? this.enabled,
    events: events ?? this.events,
    windowEnabled: windowEnabled ?? this.windowEnabled,
    windowStart: windowStart ?? this.windowStart,
    windowEnd: windowEnd ?? this.windowEnd,
    ringMinutes: ringMinutes ?? this.ringMinutes,
    excludedPrinters: excludedPrinters ?? this.excludedPrinters,
    excludedLocations: excludedLocations ?? this.excludedLocations,
  );

  AlarmPrefs withEvent(AlarmEvent e, bool on) =>
      copyWith(events: on ? {...events, e} : ({...events}..remove(e)));

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'events': [for (final e in events) e.name],
    'windowEnabled': windowEnabled,
    'windowStart': windowStart,
    'windowEnd': windowEnd,
    'ringMinutes': ringMinutes,
    'excludedPrinters': [...excludedPrinters],
    'excludedLocations': [...excludedLocations],
  };

  /// Lenient like the rest of the notification prefs: a missing or malformed
  /// field takes its default, an unknown event name is skipped.
  factory AlarmPrefs.fromJson(Object? json) {
    if (json is! Map) return defaults;
    final rawEvents = json['events'];
    return AlarmPrefs(
      enabled: json['enabled'] == true,
      events: rawEvents is List
          ? {
              for (final e in AlarmEvent.values)
                if (rawEvents.contains(e.name)) e,
            }
          : defaults.events,
      windowEnabled: json['windowEnabled'] is bool
          ? json['windowEnabled'] as bool
          : defaults.windowEnabled,
      windowStart: _minuteOfDay(json['windowStart'], defaultWindowStart),
      windowEnd: _minuteOfDay(json['windowEnd'], defaultWindowEnd),
      ringMinutes: _ringStep(json['ringMinutes']),
      excludedPrinters: {
        if (json['excludedPrinters'] case final List list)
          for (final v in list)
            if (v is int) v,
      },
      excludedLocations: {
        if (json['excludedLocations'] case final List list)
          for (final v in list)
            if (v is String && v.isNotEmpty) v,
      },
    );
  }

  // `is int` first: `contains` alone also matches 10.0, and casting that throws,
  // which would reset every notification setting, not just this one.
  static int _ringStep(Object? v) =>
      v is int && ringMinuteSteps.contains(v) ? v : defaultRingMinutes;

  static int _minuteOfDay(Object? v, int fallback) =>
      v is int && v >= 0 && v < 24 * 60 ? v : fallback;
}
