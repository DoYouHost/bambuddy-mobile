import 'package:app_util/app_util.dart';
import 'package:flutter/services.dart';

/// The print alarm (#61), over the channel to `PrintAlarm.kt`. Served on the
/// foreground service's engine (which rings) and on `MainActivity`'s (which
/// also asks about the full-screen permission). Absent in the watch flavor and
/// in tests, where every answer is "nothing rang".
class AlarmRinger {
  const AlarmRinger();

  static const _platform = PlatformQuery(
    MethodChannel('page.codeberg.morganmlgman.bambuddy/alarm'),
  );

  /// Rings until stopped or for [minutes]. Strings are already localized;
  /// [printer] names the printer on the screen and the notification, empty for
  /// none. False when nothing could ring: no host, or notifications off.
  Future<bool> ring({
    required int id,
    required String title,
    required String body,
    required String stopLabel,
    required int minutes,
    required String printer,
  }) => _platform.ask(
    'ring',
    fallback: false,
    arguments: {
      'id': id,
      'title': title,
      'body': body,
      'stop': stopLabel,
      'minutes': minutes,
      'printer': printer,
    },
  );

  /// Whether the alarm may take the whole screen over the lock screen. True
  /// when nobody answers: with no host there is no permission to ask for.
  Future<bool> canFullScreen() =>
      _platform.ask('canFullScreen', fallback: true);

  /// Opens the system page where the user grants the full-screen permission.
  Future<void> openFullScreenSettings() =>
      _platform.tell('openFullScreenSettings');
}
