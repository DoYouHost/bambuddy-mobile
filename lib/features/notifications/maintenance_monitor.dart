import '../../core/models/maintenance.dart';
import '../../core/notifications/background_api.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/maintenance_repository.dart';
import '../../l10n/app_localizations.dart';
import 'print_monitor.dart' show systemAppLocalizations;

/// Base alert IDs for maintenance — separate from print alerts (which end at
/// 11000 in [PrintMonitor]). Add item ID / printer ID to base.
const int _maintenanceDueAlertBase = 12000;
const int _maintenanceReminderAlertBase = 13000;

/// REST-based maintenance monitor running in the foreground service isolate:
/// periodically checks if any maintenance task became overdue ([check]) and fires
/// a single alert for each newly-due item. Additionally [remindOnPrintEnd]
/// provides a summary reminder when a print completes.
///
/// Dedup: persistent set of already-notified IDs — survives isolate restart
/// (no spam on reboot), and when an item is no longer due (after completion),
/// it's removed from the set (re-arm). Single alert and reminder carry a
/// "Mark done" action that resets the counter without opening the app.
class MaintenanceMonitor {
  MaintenanceMonitor(
    this._notifications, {
    required this._repo,
    required this._prefs,
    Set<int>? initialNotified,
    this.persist,
    AppLocalizations Function()? l10n,
  })  : _notified = {...?initialNotified},
        _l10n = l10n ?? systemAppLocalizations;

  final NotificationService _notifications;
  final MaintenanceRepository _repo;
  final NotificationPrefs _prefs;
  final Set<int> _notified;

  /// Persistence callback for dedup set (e.g., to SharedPreferences). `null` in tests.
  final Future<void> Function(Set<int>)? persist;
  final AppLocalizations Function() _l10n;

  bool get _enabled => _prefs.isOn(NotifEvent.maintenanceDue);

  /// Periodically check all printers. Network/parsing errors are silently skipped
  /// (dedup set not cleared, service not crashed).
  Future<void> check() async {
    if (!_enabled) return;
    final List<PrinterMaintenanceOverview> printers;
    try {
      printers = await _repo.fetchOverview();
    } on Object {
      return;
    }

    final dueNow = <int>{};
    for (final printer in printers) {
      for (final item in printer.maintenanceItems) {
        if (!item.enabled || !item.isDue) continue;
        dueNow.add(item.id);
        if (_notified.add(item.id)) {
          await _alertDue(printer, item);
        }
      }
    }
    // Items no longer due (e.g., after completion) — re-arm.
    _notified.removeWhere((id) => !dueNow.contains(id));
    await persist?.call(_notified);
  }

  /// Summary reminder when print on printer [printerId] completes: if it has
  /// overdue tasks, fire one alert (not dedup'd — intentional reminder at natural time).
  /// Fixed ID per printer.
  Future<void> remindOnPrintEnd(int printerId) async {
    if (!_enabled) return;
    final printer = await _repo.fetchPrinter(printerId);
    if (printer == null) return;
    final due = printer.dueItems;
    if (due.isEmpty) return;

    final l = _l10n();
    await _notifications.showAlert(
      id: _maintenanceReminderAlertBase + printerId,
      title: l.maintenanceReminderTitle,
      body: l.maintenanceReminderBody(printer.printerName, due.length),
      payload: maintenancePayload([for (final i in due) i.id]),
      actions: [_resetAction(l)],
    );
  }

  Future<void> _alertDue(
    PrinterMaintenanceOverview printer,
    MaintenanceStatus item,
  ) async {
    final l = _l10n();
    await _notifications.showAlert(
      id: _maintenanceDueAlertBase + item.id,
      title: l.maintenanceNotifTitle,
      body: l.maintenanceNotifBody(
        item.printerName ?? printer.printerName,
        item.maintenanceTypeName,
      ),
      payload: maintenancePayload([item.id]),
      actions: [_resetAction(l)],
    );
  }

  NotificationAction _resetAction(AppLocalizations l) => NotificationAction(
        id: maintenancePerformActionId,
        title: l.maintenanceNotifAction,
      );
}
