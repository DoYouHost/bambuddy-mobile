import 'package:app_util/app_util.dart';
import 'package:flutter/services.dart';

import '../diagnostics/notif_probe.dart';

/// What an alarm rings with: `PrintAlarm`'s own player, or the notification's
/// sound played by the system when Android refuses the player the audio focus.
/// The second is the one the next noisy notification can cut.
enum AlarmSound { player, system }

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
  /// none. Null when nothing could ring: no host, or notifications off.
  Future<AlarmSound?> ring({
    required int id,
    required String title,
    required String body,
    required String stopLabel,
    required int minutes,
    required String printer,
  }) async => _sound(
    await _platform.ask<String?>(
      'ring',
      fallback: null,
      arguments: {
        'id': id,
        'title': title,
        'body': body,
        'stop': stopLabel,
        'minutes': minutes,
        'printer': printer,
      },
    ),
  );

  static AlarmSound? _sound(String? name) =>
      AlarmSound.values.asNameMap()[name];

  /// Writes what the native side reports after a ring to the bug-report log:
  /// each stop, and a player that died mid-ring. Called once per engine that
  /// serves the alarm channel; `PrintAlarm` tells only the newest.
  static void recordReports() =>
      _platform.channel.setMethodCallHandler((call) async {
        final args = Map<String, Object?>.from(call.arguments as Map);
        final nid = args['id'] as int;
        final sound = args['sound'] as String;
        switch (call.method) {
          case 'stopped':
            NotifProbe.alarmStopped(
              nid,
              why: args['why'] as String,
              rangSeconds: args['rang_s'] as int,
              sound: sound,
            );
          case 'recovered':
            NotifProbe.alarmRecovered(nid, sound: sound);
        }
      });

  /// Whether the alarm may take the whole screen over the lock screen. True
  /// when nobody answers: with no host there is no permission to ask for.
  Future<bool> canFullScreen() =>
      _platform.ask('canFullScreen', fallback: true);

  /// Opens the system page where the user grants the full-screen permission.
  Future<void> openFullScreenSettings() =>
      _platform.tell('openFullScreenSettings');
}
