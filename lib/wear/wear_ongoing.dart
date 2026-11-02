import 'package:app_util/app_util.dart';
import 'package:flutter/services.dart';

import '../core/format/datetime_format.dart';
import '../core/notifications/ongoing_text.dart';
import '../l10n/app_localizations.dart';
import 'wear_transport.dart';

/// What the watch's Ongoing Activity shows for [fleet], or null when nothing is
/// running — the same printer and the same words as the phone's ongoing
/// notification ([ongoingText]).
Map<String, Object?>? wearOngoingArgs(
  WearFleet fleet,
  AppLocalizations l,
  DateTimeFormats formats,
  DateTime now,
) {
  final text = ongoingText(
    runningByEta(fleet.printers.map((p) => p.status).nonNulls),
    l,
    formats,
    now,
  );
  if (text == null) return null;
  final minutes = text.lead.remainingTime;
  return {
    'title': text.title,
    'body': text.body,
    'progress': text.progress,
    'chip': text.progress == null ? null : '${text.progress}%',
    'etaInMs': minutes != null && minutes > 0 ? minutes * 60000 : null,
    'paused': text.lead.isPaused,
    'channelName': l.wearOngoingChannel,
  };
}

/// The watch's ongoing notification and its Ongoing Activity (Play's WO-V4),
/// through `WearOngoing.kt` in the wear source set. The phone has no host for
/// the channel, so every call there is a no-op.
class WearOngoing {
  const WearOngoing({this.platform = _platform});

  static const _platform = PlatformQuery(
    MethodChannel('page.codeberg.morganmlgman.bambuddy/wear_ongoing'),
  );

  final PlatformQuery platform;

  /// Whether the notification went up; false when the system refused to start
  /// the service from the background.
  Future<bool> show(Map<String, Object?> args) =>
      platform.ask('show', fallback: false, arguments: args);

  Future<void> stop() => platform.tell('stop');

  /// Whether the service runs in the foreground and the system holds an
  /// Ongoing Activity for it — read from the system, for the on-device tests
  /// in patrol_test/ (which the analyzer does not count as tests).
  Future<({bool foreground, bool ongoingActivity})> status() async {
    final map = await platform.ask<Map<Object?, Object?>>(
      'status',
      fallback: const {},
    );
    return (
      foreground: map['foreground'] == true,
      ongoingActivity: map['ongoingActivity'] == true,
    );
  }

  /// Android 13+ shows nothing a service posts until this is granted.
  Future<void> requestPermission() => platform.tell('requestPermission');
}
