import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../l10n/app_locale.dart';
import 'background_sync.dart';
import 'print_monitor_task_handler.dart';

/// The foreground service's own notification. Passed explicitly because the
/// plugin otherwise picks 1000 — where the print alert bands start, so an alert
/// for the printer with that row id would take the service's notification over
/// and the next service update would wipe the alert. Kept below every band in
/// [PrintMonitor].
const int foregroundServiceNotificationId = 1;

/// Keeping print monitoring alive while the app is not in the foreground.
/// Knows no transport details on purpose — lifecycle code only calls
/// [start]/[stop].
abstract class BackgroundMonitor {
  /// Starts monitoring in the background (idempotent).
  ///
  /// Returns whether it actually started something. False means a service was
  /// already running — and one left over from before never runs its start-up
  /// code again, so anything the app decided since has not reached it.
  Future<bool> start();

  /// Stops monitoring in the background (idempotent).
  ///
  /// Returns whether it actually stopped something. Callers log against this
  /// rather than against having asked, so a stop only reaches the record when a
  /// service really ended.
  Future<bool> stop();

  /// Whether monitoring is currently running.
  Future<bool> isRunning();

  /// Tells a monitor that is already running to re-read [what] from preferences.
  ///
  /// Why it is needed at all is [BackgroundSync]'s own doc.
  void sync(BackgroundSync what);
}

/// Hosts [PrintMonitorTaskHandler] in its own isolate inside a real Android
/// foreground service.
class ForegroundServiceMonitor implements BackgroundMonitor {
  @override
  Future<bool> start() async {
    if (await FlutterForegroundTask.isRunningService) return false;
    final l10n = systemAppLocalizations();
    await FlutterForegroundTask.startService(
      serviceId: foregroundServiceNotificationId,
      // Must name the same type the manifest declares, or `startForeground`
      // throws on Android 14+. Why this one rather than `dataSync` is in the
      // manifest, next to the declaration.
      serviceTypes: const [ForegroundServiceTypes.connectedDevice],
      notificationTitle: l10n.bgServiceTitle,
      notificationText: l10n.bgServiceText,
      callback: startCallback,
    );
    return true;
  }

  /// Over the communication port `main` already opens — the only way to reach an
  /// isolate that is past its own start-up.
  @override
  void sync(BackgroundSync what) =>
      FlutterForegroundTask.sendDataToTask(what.message);

  @override
  Future<bool> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return false;
    await FlutterForegroundTask.stopService();
    return true;
  }

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;
}
