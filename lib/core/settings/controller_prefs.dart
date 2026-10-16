/// The single-printer controller's own settings, kept per device
/// ([docs/single-printer-controller.md] §4). One JSON object, so a damaged
/// field costs that field and nothing else.
class ControllerPrefs {
  const ControllerPrefs({
    this.saverAfterMinutes = defaultSaverAfterMinutes,
    this.saverBrightness = defaultSaverBrightness,
    this.wakeOnWarnings = true,
    this.keepAwake = true,
    this.liveCamera = true,
  });

  /// Idle times the picker offers, then [saverNever]. Provisional: the
  /// maintainer has not settled the list.
  static const saverAfterChoices = [1, 2, 5, 10, 15];
  static const defaultSaverAfterMinutes = 5;

  /// The saver never starts. Choosing it is a risk to the panel, so the picker
  /// must make the user confirm it (a burn-in warning) before it is stored.
  static const saverNever = 0;

  static const saverAfterOptions = [...saverAfterChoices, saverNever];

  /// Brightness range of the saver, in percent.
  static const minSaverBrightness = 10;
  static const maxSaverBrightness = 100;
  static const saverBrightnessStep = 5;
  static const defaultSaverBrightness = 25;

  /// Minutes of idle time before the saver, or [saverNever].
  final int saverAfterMinutes;
  final int saverBrightness;

  /// Whether a fault that does not pause the print also wakes the screen.
  /// Faults that pause it always do, so this is not a way to miss one.
  final bool wakeOnWarnings;

  final bool keepAwake;

  /// Off shows the file's cover instead of the stream.
  final bool liveCamera;

  /// Null when the saver never starts.
  Duration? get saverAfter => saverAfterMinutes == saverNever
      ? null
      : Duration(minutes: saverAfterMinutes);

  ControllerPrefs copyWith({
    int? saverAfterMinutes,
    int? saverBrightness,
    bool? wakeOnWarnings,
    bool? keepAwake,
    bool? liveCamera,
  }) => ControllerPrefs(
    saverAfterMinutes: saverAfterMinutes ?? this.saverAfterMinutes,
    saverBrightness: saverBrightness ?? this.saverBrightness,
    wakeOnWarnings: wakeOnWarnings ?? this.wakeOnWarnings,
    keepAwake: keepAwake ?? this.keepAwake,
    liveCamera: liveCamera ?? this.liveCamera,
  );

  /// Anything unreadable falls back to that field's default; a time that is not
  /// on the picker does too, because the picker could not show it.
  factory ControllerPrefs.fromJson(Map<String, dynamic> json) {
    final after = json['saver_after_minutes'];
    final brightness = json['saver_brightness'];
    return ControllerPrefs(
      saverAfterMinutes: after is int && saverAfterOptions.contains(after)
          ? after
          : defaultSaverAfterMinutes,
      saverBrightness: brightness is int
          ? brightness.clamp(minSaverBrightness, maxSaverBrightness)
          : defaultSaverBrightness,
      wakeOnWarnings: json['wake_on_warnings'] is bool
          ? json['wake_on_warnings'] as bool
          : true,
      keepAwake: json['keep_awake'] is bool ? json['keep_awake'] as bool : true,
      liveCamera: json['live_camera'] is bool
          ? json['live_camera'] as bool
          : true,
    );
  }

  Map<String, dynamic> toJson() => {
    'saver_after_minutes': saverAfterMinutes,
    'saver_brightness': saverBrightness,
    'wake_on_warnings': wakeOnWarnings,
    'keep_awake': keepAwake,
    'live_camera': liveCamera,
  };
}
