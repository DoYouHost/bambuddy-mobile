import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../features/notifications/print_monitor.dart' show systemAppLocalizations;
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

  /// Tells a monitor that is already running to re-read the diagnostics session.
  ///
  /// The session id travels through `SharedPreferences`, which the background
  /// isolate reads once when it starts. That is enough when the service starts
  /// after the recording did — and silently wrong when it was already up, which is
  /// the normal state for anyone who has ever swiped the app away: Android
  /// restarts the service and it outlives the next launch. Without this the
  /// background half of their report is simply absent, and absent looks exactly
  /// like "the service did nothing".
  void syncDiagnostics();

  /// Tells a monitor that is already running to re-read the 12/24-hour switch.
  ///
  /// Same shape as [syncDiagnostics] and for the same reason: the value travels
  /// through `SharedPreferences`, and a service that outlived the launch which
  /// wrote it never reads that file again on its own.
  void syncClockFormat();
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
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: l10n.bgServiceTitle,
      notificationText: l10n.bgServiceText,
      callback: startCallback,
    );
    return true;
  }

  /// Over the communication port `main` already opens — the only way to reach an
  /// isolate that is past its own start-up.
  @override
  void syncDiagnostics() =>
      FlutterForegroundTask.sendDataToTask(const {'diagnostics': 'sync'});

  @override
  void syncClockFormat() =>
      FlutterForegroundTask.sendDataToTask(const {'clock': 'sync'});

  @override
  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;
}
