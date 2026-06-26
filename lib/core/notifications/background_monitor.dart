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
abstract class BackgroundMonitor {
  /// Starts monitoring in the background (idempotent).
  Future<void> start();

  /// Stops monitoring in the background (idempotent).
  Future<void> stop();

  /// Whether monitoring is currently running.
  Future<bool> isRunning();
}

/// Implementation using `flutter_foreground_task`: hosts [PrintMonitorTaskHandler]
/// in a separate isolate inside an actual Android foreground service.
class ForegroundServiceMonitor implements BackgroundMonitor {
  @override
  Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) return;
    final l10n = systemAppLocalizations();
    await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: l10n.bgServiceTitle,
      notificationText: l10n.bgServiceText,
      callback: startCallback,
    );
  }

  @override
  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;
}
