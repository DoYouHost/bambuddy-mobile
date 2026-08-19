import '../../core/diagnostics/notif_probe.dart';
import '../../core/models/maintenance.dart';
import '../../core/notifications/background_api.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/maintenance_repository.dart';
import '../../l10n/app_localizations.dart';
import 'print_monitor.dart' show alertBandWidth, systemAppLocalizations;

/// Base alert IDs for maintenance — the two bands after the print alerts, which
/// end at 11 × [alertBandWidth] in [PrintMonitor]. Add item ID / printer ID to
/// base. The due band's offset is a `printer_maintenance` row id, the fastest
/// growing of them all: the server adds a row per printer per task type on every
/// overview it serves, so this is the band that most needs its width.
const int _maintenanceDueAlertBase = 12 * alertBandWidth;
const int _maintenanceReminderAlertBase = 13 * alertBandWidth;

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
    this.reload,
    AppLocalizations Function()? l10n,
  })  : _notified = {...?initialNotified},
        _l10n = l10n ?? systemAppLocalizations;

  final NotificationService _notifications;
  final MaintenanceRepository _repo;
  final NotificationPrefs _prefs;
  final Set<int> _notified;

  /// Persistence callback for dedup set (e.g., to SharedPreferences). `null` in tests.
  final Future<void> Function(Set<int>)? persist;

  /// Reloads the persisted dedup set from disk. Needed because the
  /// notification-action callback (a *separate* isolate — see
  /// `handleMaintenanceAction`) also removes ids from the same persisted set
  /// after "Mark Done", but can't reach this monitor's in-memory `_notified`
  /// directly. Without re-syncing, this monitor would keep treating an item
  /// as "already notified" and skip a legitimate re-alert if it becomes due
  /// again before the self-healing `removeWhere` below next clears it (i.e.
  /// before the server ever reports `is_due=false` for that item). `null` in tests.
  final Future<Set<int>> Function()? reload;
  final AppLocalizations Function() _l10n;

  bool get _enabled => _prefs.isOn(NotifEvent.maintenanceDue);

  /// Periodically check all printers. Network/parsing errors are silently skipped
  /// (dedup set not cleared, service not crashed).
  Future<void> check() async {
    if (!_enabled) return;
    final List<PrinterMaintenanceOverview> printers;
    try {
      printers = await _repo.fetchOverview();
    } on Object catch (error) {
      // The only witness that a poll happened at all: with a 30-minute interval,
      // a failure here means no maintenance alert for half an hour and nothing
      // else records it. The request itself is logged by `HttpProbe`; this says
      // the alert decision was skipped.
      NotifProbe.suppressed(
        NotifSkip.fetchFailed,
        event: NotifEvent.maintenanceDue,
        fields: {'cause': error.runtimeType.toString()},
      );
      return;
    }

    // After the fetch, not before it: the request takes seconds, and a "Mark
    // Done" tapped inside that window rewrites this very set from the callback
    // isolate. Reading first and writing at the end would hand back the state we
    // started with and undo it.
    final synced = await reload?.call();
    if (synced != null) {
      _notified
        ..clear()
        ..addAll(synced);
    }

    final dueNow = <int>{};
    var fresh = 0;
    for (final printer in printers) {
      for (final item in printer.maintenanceItems) {
        if (!item.enabled || !item.isDue) continue;
        dueNow.add(item.id);
        if (_notified.add(item.id)) {
          fresh++;
          await _alertDue(printer, item);
        }
      }
    }
    // One record for the whole poll rather than one per de-duplicated item: N
    // lines saying "already told you" carry no more than these two numbers.
    NotifProbe.maintenanceCheck(due: dueNow.length, fresh: fresh);
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
    if (printer == null) {
      // `noData`, not `fetchFailed`: the repository degrades to null for an
      // unknown printer *and* for a transport error, and the log must not claim
      // to know which. Nothing is recorded when the printer is known and simply
      // has nothing overdue — that is the ordinary outcome, not a gap.
      NotifProbe.suppressed(
        NotifSkip.noData,
        printerId: printerId,
        event: NotifEvent.maintenanceDue,
      );
      return;
    }
    final due = printer.dueItems;
    if (due.isEmpty) return;

    final l = _l10n();
    // Both notifications this class posts report `maintenanceDue`: the event enum
    // is a persisted preference key, so a second value would silently land in the
    // default-off set and disable the reminder for every existing install. The id
    // band is what tells them apart in a log.
    await _notifications.showAlert(
      event: NotifEvent.maintenanceDue,
      printerId: printerId,
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
      event: NotifEvent.maintenanceDue,
      printerId: printer.printerId,
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
