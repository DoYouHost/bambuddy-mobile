import 'package:bambuddy_mobile/core/models/maintenance.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:bambuddy_mobile/features/notifications/maintenance_monitor.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nagrywa alerty zamiast dotykać pluginu.
class _FakeNotifications implements NotificationService {
  final alerts = <Map<String, Object?>>[];

  @override
  Future<void> showAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
    List<NotificationAction>? actions,
  }) async {
    alerts.add({
      'id': id,
      'body': body,
      'payload': payload,
      'actionIds': [for (final a in actions ?? const []) a.id],
    });
  }

  @override
  Future<void> clearOngoing() async {}
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) async {}
}

/// Repo sterowane z testu: zwraca podstawioną listę / drukarkę.
class _FakeRepo extends MaintenanceRepository {
  _FakeRepo() : super(Dio());

  List<PrinterMaintenanceOverview> overview = const [];

  @override
  Future<List<PrinterMaintenanceOverview>> fetchOverview() async => overview;

  @override
  Future<PrinterMaintenanceOverview?> fetchPrinter(int printerId) async {
    for (final p in overview) {
      if (p.printerId == printerId) return p;
    }
    return null;
  }
}

MaintenanceStatus _item({
  required int id,
  bool isDue = false,
  bool enabled = true,
}) =>
    MaintenanceStatus(
      id: id,
      printerId: 1,
      printerName: 'X2D',
      maintenanceTypeId: id,
      maintenanceTypeName: 'Task $id',
      enabled: enabled,
      isDue: isDue,
    );

PrinterMaintenanceOverview _printer(List<MaintenanceStatus> items) =>
    PrinterMaintenanceOverview(
      printerId: 1,
      printerName: 'X2D',
      maintenanceItems: items,
      dueCount: items.where((i) => i.isDue).length,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNotifications notifications;
  late _FakeRepo repo;
  late Set<int> persisted;

  MaintenanceMonitor monitor({NotificationPrefs? prefs}) => MaintenanceMonitor(
        notifications,
        repo: repo,
        prefs: prefs ??
            const NotificationPrefs(enabled: {NotifEvent.maintenanceDue}),
        initialNotified: persisted,
        persist: (s) async => persisted = {...s},
        l10n: () => lookupAppLocalizations(const Locale('en')),
      );

  setUp(() {
    notifications = _FakeNotifications();
    repo = _FakeRepo();
    persisted = {};
  });

  test('check: alarmuje nowo-due i dokłada akcję resetu', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true), _item(id: 11)]),
    ];

    await monitor().check();

    expect(notifications.alerts, hasLength(1));
    final alert = notifications.alerts.single;
    expect(alert['payload'], '10');
    expect(alert['actionIds'], [maintenancePerformActionId]);
    expect(persisted, {10});
  });

  test('check: dedup — drugie sprawdzenie nie powtarza alertu', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];

    final m = monitor();
    await m.check();
    await m.check();

    expect(notifications.alerts, hasLength(1));
  });

  test('check: re-arm — gdy pozycja przestaje być due, znika z dedup', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];
    final m1 = monitor();
    await m1.check();
    expect(persisted, {10});

    // Wykonano konserwację → już nie due.
    repo.overview = [
      _printer([_item(id: 10)]),
    ];
    await m1.check();
    expect(persisted, isEmpty);
  });

  test('check: wyłączone zdarzenie → cisza', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];

    await monitor(prefs: const NotificationPrefs(enabled: {})).check();

    expect(notifications.alerts, isEmpty);
  });

  test('check: pozycja wyłączona (enabled=false) nie alarmuje', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true, enabled: false)]),
    ];

    await monitor().check();

    expect(notifications.alerts, isEmpty);
  });

  test('remindOnPrintEnd: zbiorcze przypomnienie gdy są zaległe', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true), _item(id: 12, isDue: true)]),
    ];

    await monitor().remindOnPrintEnd(1);

    final alert = notifications.alerts.single;
    expect(alert['id'], 13000 + 1);
    expect(alert['payload'], '10,12');
    expect(alert['actionIds'], [maintenancePerformActionId]);
  });

  test('remindOnPrintEnd: brak zaległych → brak powiadomienia', () async {
    repo.overview = [
      _printer([_item(id: 10)]),
    ];

    await monitor().remindOnPrintEnd(1);

    expect(notifications.alerts, isEmpty);
  });
}
