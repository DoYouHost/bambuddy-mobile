import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../features/notifications/print_monitor.dart' show systemAppLocalizations;
import 'print_monitor_task_handler.dart';

/// Mechanizm utrzymujący monitoring wydruków, gdy aplikacja nie jest na
/// pierwszym planie. Abstrakcja celowo nie zna szczegółów transportu — kod
/// cyklu życia woła tylko [start]/[stop].
///
/// Furtka na push: w przyszłości obok [ForegroundServiceMonitor] może powstać
/// `PushMonitor implements BackgroundMonitor`, który zamiast trzymać foreground
/// service rejestruje urządzenie do powiadomień po stronie serwera (ntfy/FCM).
/// Wtedy wystarczy podmienić implementację w `backgroundMonitorProvider` —
/// reszta aplikacji nie drgnie. (Tu NIE implementujemy nic z push.)
abstract class BackgroundMonitor {
  /// Rozpoczyna monitoring w tle (idempotentne — gdy już działa, nic nie robi).
  Future<void> start();

  /// Zatrzymuje monitoring w tle (idempotentne).
  Future<void> stop();

  /// Czy monitoring w tle aktualnie działa.
  Future<bool> isRunning();
}

/// Implementacja na `flutter_foreground_task`: hostuje [PrintMonitorTaskHandler]
/// w osobnym isolacie wewnątrz prawdziwego Android foreground service.
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
