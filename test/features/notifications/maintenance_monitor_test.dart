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

/// Records alerts instead of touching the plugin.
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

/// Repo driven from the test: returns the injected list / printer.
class _FakeRepo extends MaintenanceRepository {
  _FakeRepo() : super(Dio());

  List<PrinterMaintenanceOverview> overview = const [];

  /// Forces a network error on the overview — the repo lets it through, as in
  /// production.
  bool failOverview = false;

  /// Fires during the request so the test can slip in an event from another
  /// isolate — like tapping "Mark Done" on the notification.
  void Function()? onFetch;

  @override
  Future<List<PrinterMaintenanceOverview>> fetchOverview() async {
    if (failOverview) {
      throw DioException(requestOptions: RequestOptions(path: '/maintenance'));
    }
    onFetch?.call();
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

  test('check: alerts on newly-due items and adds the reset action', () async {
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

  test('check: dedup — a second check does not repeat the alert', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];

    final m = monitor();
    await m.check();
    await m.check();

    expect(notifications.alerts, hasLength(1));
  });

  test('check: re-arm — an item that stops being due leaves the dedup set', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];
    final m1 = monitor();
    await m1.check();
    expect(persisted, {10});

    // Maintenance performed → no longer due.
    repo.overview = [
      _printer([_item(id: 10)]),
    ];
    await m1.check();
    expect(persisted, isEmpty);
  });

  test('check: reload from disk unblocks the alert after "Mark Done" in another '
      'isolate',
      () async {
    // The item is still due on the server (perform failed), but the notification
    // callback took it out of the set on disk — the poll must see that and alert
    // again.
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];
    persisted = {10};
    var onDisk = {10};

    final m = monitor(reload: () async => {...onDisk});
    await m.check();
    expect(notifications.alerts, isEmpty, reason: 'dedup: already reported');

    onDisk = {};
    await m.check();

    expect(notifications.alerts, hasLength(1));
  });

  test('check: "Mark Done" during the request is not lost under the write',
      () async {
    // The request takes seconds; a tap inside that window rewrites this very set
    // from the callback isolate. Reading before the request would hand back the
    // state we started with and undo that write.
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];
    persisted = {10};
    var onDisk = {10};
    repo.onFetch = () => onDisk = {}; // the user taps mid-fetch

    await monitor(reload: () async => {...onDisk}).check();

    expect(notifications.alerts, hasLength(1), reason: 'item re-armed');
  });

  test('check: "Mark Done" after the request is not lost under the write either',
      () async {
    // Same situation as above, only the tap lands after the read: between it and
    // the final write. The write must therefore start from disk, not from the copy
    // this poll started with — otherwise an item taken out of the set comes back
    // into it and a counter that was never reset stays silent forever.
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];
    persisted = {10};
    var onDisk = {10};
    var reads = 0;

    await monitor(reload: () async {
      final snapshot = {...onDisk};
      if (reads++ == 0) onDisk = {}; // tap right after the read
      return snapshot;
    }).check();

    expect(reads, 2, reason: 'read at the start and again before the write');
    expect(persisted, isEmpty, reason: 're-arm from another isolate survived the write');
  });

  test('check: a disabled event → silence', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true)]),
    ];

    await monitor(prefs: const NotificationPrefs(enabled: {})).check();

    expect(notifications.alerts, isEmpty);
  });

  test('check: a disabled item (enabled=false) does not alert', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true, enabled: false)]),
    ];

    await monitor().check();

    expect(notifications.alerts, isEmpty);
  });

  test('a large task id does not stray into the reminder band', () async {
    // `printer_maintenance.id` is an autoincrement with no ceiling — the server
    // adds a row per printer per task type on every overview, and numbers freed by
    // deleted printers never come back. With a band width of 1000, item 1001 got
    // printer 1's reminder id and replaced it, putting someone else's task list
    // behind the "Mark Done" button.
    repo.overview = [
      _printer([_item(id: 1001, isDue: true)]),
    ];

    await monitor().check();

    final id = notifications.alerts.single['id']! as int;
    expect(id, greaterThanOrEqualTo(12 * alertBandWidth));
    expect(id, lessThan(13 * alertBandWidth));
  });

  test('remindOnPrintEnd: one summary reminder when items are overdue', () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true), _item(id: 12, isDue: true)]),
    ];

    await monitor().remindOnPrintEnd(1);

    final alert = notifications.alerts.single;
    expect(alert['id'], 13 * alertBandWidth + 1);
    expect(alert['payload'], '10,12');
    expect(alert['actionIds'], [maintenancePerformActionId]);
  });

  test('remindOnPrintEnd: nothing overdue → no notification', () async {
    repo.overview = [
      _printer([_item(id: 10)]),
    ];

    await monitor().remindOnPrintEnd(1);

    expect(notifications.alerts, isEmpty);
  });

  test(
      'remindOnPrintEnd: a disabled item (enabled=false) is skipped even when due',
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
      'remindOnPrintEnd: every overdue item disabled → no notification',
      () async {
    repo.overview = [
      _printer([_item(id: 10, isDue: true, enabled: false)]),
    ];

    await monitor().remindOnPrintEnd(1);

    expect(notifications.alerts, isEmpty);
  });

  group('diagnostics', () {
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

    test('one record per overview, not per de-duplicated item', () async {
      repo.overview = [
        _printer([
          _item(id: 10, isDue: true),
          _item(id: 11, isDue: true),
          _item(id: 12),
        ]),
      ];
      persisted = {10}; // 10 already reported, 11 is new

      final all = await rows(() => monitor().check());

      final check = [for (final r in all) if (r['evt'] == 'maintenance_check') r];
      expect(check.single['due'], 2);
      expect(check.single['fresh'], 1);
    });

    test('a failed overview leaves a reason, not silence', () async {
      repo.failOverview = true;

      final all = await rows(() => monitor().check());

      final skip = [for (final r in all) if (r['evt'] == 'suppressed') r];
      expect(skip.single['reason'], 'fetchFailed');
      expect(skip.single['event'], 'maintenanceDue');
      expect(skip.single['cause'], 'DioException');
      // The overview never finished, so there is nothing to report on.
      expect([for (final r in all) if (r['evt'] == 'maintenance_check') r],
          isEmpty);
    });

    test('no printer data is noData, not fetchFailed', () async {
      // The server does not know the printer, or the connection failed — the
      // repository returns null in both cases, so the log does not pretend to know
      // which.
      final all = await rows(() => monitor().remindOnPrintEnd(99));

      final skip = [for (final r in all) if (r['evt'] == 'suppressed') r];
      expect(skip.single['reason'], 'noData');
      expect(skip.single['printer_id'], 99);
    });

    test('a printer with nothing overdue leaves no record', () async {
      // An ordinary outcome, not an information gap: silence is the right answer.
      repo.overview = [
        _printer([_item(id: 10)]),
      ];

      final all = await rows(() => monitor().remindOnPrintEnd(1));

      expect(all, isEmpty);
    });
  });
}
