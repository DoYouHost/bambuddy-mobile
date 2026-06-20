import '../../core/models/maintenance.dart';
import '../../core/notifications/background_api.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/maintenance_repository.dart';
import '../../l10n/app_localizations.dart';
import 'print_monitor.dart' show systemAppLocalizations;

/// Bazy id alertów konserwacji — rozłączne z alertami wydruku (te kończą się na
/// 11000 w [PrintMonitor]). Do bazy dodajemy id pozycji / drukarki.
const int _maintenanceDueAlertBase = 12000;
const int _maintenanceReminderAlertBase = 13000;

/// REST-owy monitor konserwacji żyjący w isolacie foreground service'u: cyklicznie
/// sprawdza, czy któraś czynność stała się przeterminowana ([check]), i puszcza
/// pojedynczy alert dla każdej nowo-due pozycji. Dodatkowo [remindOnPrintEnd]
/// daje zbiorcze przypomnienie po zakończeniu wydruku.
///
/// Dedup: persystentny zbiór id już zgłoszonych — przeżywa restart isolate'u
/// (brak ponownego spamu), a gdy pozycja przestaje być due (po wykonaniu), jest
/// stąd usuwana (re-arm). Pojedynczy alert i przypomnienie niosą akcję
/// „Oznacz wykonane" resetującą licznik bez otwierania apki.
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

  /// Zapis dedup-zbioru (np. do SharedPreferences). `null` w testach.
  final Future<void> Function(Set<int>)? persist;
  final AppLocalizations Function() _l10n;

  bool get _enabled => _prefs.isOn(NotifEvent.maintenanceDue);

  /// Periodyczne sprawdzenie wszystkich drukarek. Błąd sieci/parsowania →
  /// cicho pomijamy turę (nie czyścimy dedup-zbioru, nie wywracamy serwisu).
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
    // Pozycje, które przestały być due (np. po wykonaniu) — re-arm.
    _notified.removeWhere((id) => !dueNow.contains(id));
    await persist?.call(_notified);
  }

  /// Zbiorcze przypomnienie po zakończeniu wydruku na drukarce [printerId]:
  /// jeśli ma przeterminowane czynności — jeden alert (NIE dedupowany, to
  /// celowe przypomnienie w naturalnym momencie). Stały id per drukarka.
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
