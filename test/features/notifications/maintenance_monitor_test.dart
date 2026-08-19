import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/models/maintenance.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/notifications/maintenance_monitor.dart';
import 'package:bambuddy_mobile/features/notifications/print_monitor.dart'
    show alertBandWidth;
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nagrywa alerty zamiast dotykać pluginu.
class _FakeNotifications implements NotificationService {
  final alerts = <Map<String, Object?>>[];

  @override
  Future<void> showAlert({
    required NotifEvent event,
    required int printerId,
    required int id,
    required String title,
    required String body,
    String? payload,
    List<NotificationAction>? actions,
    AlertPicture? picture,
  }) async {
    alerts.add({
      'event': event,
      'printerId': printerId,
      'id': id,
      'body': body,
      'payload': payload,
      'actionIds': [for (final a in actions ?? const []) a.id],
    });
  }

  @override
  Future<bool> isAlertActive(int id) async => true;

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

  /// Wymusza błąd sieci na przeglądzie — repo puszcza go dalej, jak w produkcji.
  bool failOverview = false;

  @override
  Future<List<PrinterMaintenanceOverview>> fetchOverview() async {
    if (failOverview) {
      throw DioException(requestOptions: RequestOptions(path: '/maintenance'));
    }
    return overview;
  }

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

  MaintenanceMonitor monitor({
    NotificationPrefs? prefs,
    Future<Set<int>> Function()? reload,
  }) =>
      MaintenanceMonitor(
        notifications,
        repo: repo,
        prefs: prefs ??
            const NotificationPrefs(enabled: {NotifEvent.maintenanceDue}),
        initialNotified: persisted,
        persist: (s) async => persisted = {...s},
        reload: reload,
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

  test('check: reload z dysku odblokowuje alert po "Mark Done" w innym izolacie',
      () async {
    // Pozycja nadal due na serwerze (perform padł), ale callback z powiadomienia
    // zdjął ją z zestawu na dysku — poll musi to zobaczyć i zaalarmować ponownie.
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];
    persisted = {10};
    var onDisk = {10};

    final m = monitor(reload: () async => {...onDisk});
    await m.check();
    expect(notifications.alerts, isEmpty, reason: 'dedup: już zgłoszone');

    onDisk = {};
    await m.check();

    expect(notifications.alerts, hasLength(1));
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

  test('duże id zadania nie wchodzi w pasmo przypomnień', () async {
    // `printer_maintenance.id` to autoinkrement bez sufitu — serwer dokłada
    // wiersz na drukarkę na każdy typ zadania przy każdym przeglądzie, a numery
    // po skasowanych drukarkach nie wracają. Przy paśmie szerokości 1000
    // pozycja 1001 dostawała id przypomnienia drukarki 1 i je podmieniała,
    // podstawiając pod przycisk „Oznacz wykonane" cudzą listę zadań.
    repo.overview = [
      _printer([_item(id: 1001, isDue: true)]),
    ];

    await monitor().check();

    final id = notifications.alerts.single['id']! as int;
    expect(id, greaterThanOrEqualTo(12 * alertBandWidth));
    expect(id, lessThan(13 * alertBandWidth));
  });

  test('remindOnPrintEnd: zbiorcze przypomnienie gdy są zaległe', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true), _item(id: 12, isDue: true)]),
    ];

    await monitor().remindOnPrintEnd(1);

    final alert = notifications.alerts.single;
    expect(alert['id'], 13 * alertBandWidth + 1);
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

  test(
      'remindOnPrintEnd: pozycja wyłączona (enabled=false) pomijana mimo due',
      () async {
    repo.overview = [
      _printer([
        _item(id: 10, isDue: true, enabled: false),
        _item(id: 12, isDue: true),
      ]),
    ];

    await monitor().remindOnPrintEnd(1);

    final alert = notifications.alerts.single;
    expect(alert['payload'], '12');
  });

  test(
      'remindOnPrintEnd: wszystkie zaległe wyłączone → brak powiadomienia',
      () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true, enabled: false)]),
    ];

    await monitor().remindOnPrintEnd(1);

    expect(notifications.alerts, isEmpty);
  });

  group('diagnostyka', () {
    late DiagnosticRecorder recorder;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      recorder = DiagnosticRecorder(
        settings: SettingsRepository(await SharedPreferences.getInstance()),
        loadFacts: () async =>
            const SessionFacts(app: '0.11.3+1103', flavor: 'mobile'),
        resolveDirectory: () async => null,
      );
    });

    tearDown(() => recorder.discard());

    Future<List<Map<String, Object?>>> rows(Future<void> Function() body) async {
      await recorder.start();
      await body();
      return [
        for (final line in const LineSplitter().convert(await recorder.stop()))
          if (jsonDecode(line) case final Map<String, Object?> row
              when row['src'] == 'notif')
            row,
      ];
    }

    test('jeden rekord na przegląd, nie na zdeduplikowany element', () async {
      repo.overview = [
        _printer([
          _item(id: 10, isDue: true),
          _item(id: 11, isDue: true),
          _item(id: 12),
        ]),
      ];
      persisted = {10}; // 10 już zgłoszone, 11 jest nowe

      final all = await rows(() => monitor().check());

      final check = [for (final r in all) if (r['evt'] == 'maintenance_check') r];
      expect(check.single['due'], 2);
      expect(check.single['fresh'], 1);
    });

    test('padnięty przegląd zostawia powód, nie ciszę', () async {
      repo.failOverview = true;

      final all = await rows(() => monitor().check());

      final skip = [for (final r in all) if (r['evt'] == 'suppressed') r];
      expect(skip.single['reason'], 'fetchFailed');
      expect(skip.single['event'], 'maintenanceDue');
      expect(skip.single['cause'], 'DioException');
      // Przegląd nie doszedł do końca, więc nie ma o czym raportować.
      expect([for (final r in all) if (r['evt'] == 'maintenance_check') r],
          isEmpty);
    });

    test('brak danych o drukarce to noData, nie fetchFailed', () async {
      // Serwer nie zna drukarki albo połączenie padło — repozytorium zwraca null
      // w obu przypadkach, więc log nie udaje, że wie który.
      final all = await rows(() => monitor().remindOnPrintEnd(99));

      final skip = [for (final r in all) if (r['evt'] == 'suppressed') r];
      expect(skip.single['reason'], 'noData');
      expect(skip.single['printer_id'], 99);
    });

    test('drukarka bez zaległości nie zostawia rekordu', () async {
      // Zwyczajny wynik, nie luka informacyjna: cisza jest tu poprawną odpowiedzią.
      repo.overview = [
        _printer([_item(id: 10)]),
      ];

      final all = await rows(() => monitor().remindOnPrintEnd(1));

      expect(all, isEmpty);
    });
  });
}
