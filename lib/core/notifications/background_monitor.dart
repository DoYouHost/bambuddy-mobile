import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../features/notifications/print_monitor.dart' show systemAppLocalizations;
import 'background_sync.dart';
import 'print_monitor_task_handler.dart';

/// Mechanism for maintaining print monitoring when the app is not in the foreground.
/// The abstraction intentionally doesn't know transport details — lifecycle code
/// only calls [start]/[stop].
///
/// Future extension point: `PushMonitor implements BackgroundMonitor` could
/// register the device for server-side notifications (ntfy/FCM) instead of
/// holding a foreground service. Then swapping the implementation in
/// `backgroundMonitorProvider` would work without changes to the rest of the app.
/// The foreground service's own notification. Passed explicitly because the
/// plugin otherwise picks 1000 for itself — which is where the print alert bands
/// start, so an alert for the printer with that row id would have taken the
/// service's notification over and the next service update would have wiped the
/// alert. Kept below every band in [PrintMonitor].
const int foregroundServiceNotificationId = 1;

abstract class BackgroundMonitor {
  /// Starts monitoring in the background (idempotent).
  ///
  /// Returns whether it actually started something. False means monitoring was
  /// already running — which matters more than it looks: a service left over from
  /// before never runs its start-up code again, so anything the app decided since
  /// then has not reached it.
  Future<bool> start();

  /// Stops monitoring in the background (idempotent).
  Future<void> stop();

  /// Whether monitoring is currently running.
  Future<bool> isRunning();

  /// Tells a monitor that is already running to re-read [what] from preferences.
  ///
  /// Why it is needed at all is [BackgroundSync]'s own doc. The first fact to
  /// need it was the diagnostics session: without this, the background half of a
  /// bug report is simply absent for anyone who has ever swiped the app away,
  /// and absent looks exactly like "the service did nothing".
  void sync(BackgroundSync what);
}

/// Implementation using `flutter_foreground_task`: hosts [PrintMonitorTaskHandler]
/// in a separate isolate inside an actual Android foreground service.
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
  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;
}
