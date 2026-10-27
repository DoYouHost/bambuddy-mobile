import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/maintenance.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/l10n/error_messages.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_screen.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_settings.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets of the maintenance status screen and of
/// its settings, over the demo server: the printer cards closed and open, a
/// muted task, the perform dialog, the history sheet (empty, with an entry and
/// failed), the empty and failed lists; and on the settings side the type list,
/// the create and edit sheets with their errors and menus, the interval dialog
/// and both confirmations. Deliberately not covered: the snackbars that report a
/// write, which are transient.
void main() {
  // The demo is process-wide and the performing and muting tests write to it.

  // --- Status screen ---

  a11ySurface(
    'maintenance',
    home: () => const MaintenanceScreen(),
    shows: byLogId('maintenance.printer_toggle'),
  );

  a11ySurface(
    'maintenance, every printer opened',
    home: () => const MaintenanceScreen(),
    arrange: _openEveryPrinter,
    shows: byLogId('maintenance.perform'),
  );

  a11ySurface(
    'maintenance, a muted and an overdue task',
    // A lone printer's card opens by itself.
    overrides: [_overviewOverride(() => _overview)],
    home: () => const MaintenanceScreen(),
    shows: find.text('Grease Lead Screws'),
  );

  a11ySurface(
    'maintenance, perform dialog',
    home: () => const MaintenanceScreen(),
    arrange: (tester) async {
      await _openEveryPrinter(tester);
      await tester.tap(byLogId('maintenance.perform').first);
    },
    shows: find.text(pl.maintenancePerformConfirm),
  );

  a11ySurface(
    'maintenance, history sheet without entries',
    home: () => const MaintenanceScreen(),
    arrange: (tester) async {
      await _openEveryPrinter(tester);
      await tester.tap(byLogId('maintenance.task').first);
    },
    shows: find.text(pl.maintenanceHistoryEmpty),
  );

  a11ySurface(
    'maintenance, history sheet with entries',
    overrides: [
      maintenanceHistoryProvider.overrideWith(
        (ref, id) async => const [
          MaintenanceHistoryEntry(
            id: 1,
            printerMaintenanceId: 1,
            performedAt: '2026-10-01T09:30:00Z',
            hoursAtMaintenance: 300,
            notes: 'Wiped and lubricated both rods',
          ),
          MaintenanceHistoryEntry(
            id: 2,
            printerMaintenanceId: 1,
            performedAt: '2026-08-12T17:05:00Z',
            hoursAtMaintenance: 48,
          ),
        ],
      ),
    ],
    home: () => const MaintenanceScreen(),
    arrange: (tester) async {
      await _openEveryPrinter(tester);
      await tester.tap(byLogId('maintenance.task').first);
    },
    shows: find.text('Wiped and lubricated both rods'),
  );

  a11ySurface(
    'maintenance, history failed',
    overrides: [
      maintenanceHistoryProvider.overrideWith(
        (ref, id) async =>
            throw const ApiException(AppErrorCode.connectionError),
      ),
    ],
    home: () => const MaintenanceScreen(),
    arrange: (tester) async {
      await _openEveryPrinter(tester);
      await tester.tap(byLogId('maintenance.task').first);
    },
    shows: find.text(_unreachable),
  );

  a11ySurface(
    'maintenance, no printers',
    overrides: [_overviewOverride(() => const [])],
    home: () => const MaintenanceScreen(),
    shows: find.text(pl.maintenanceEmpty),
  );

  a11ySurface(
    'maintenance, list failed',
    overrides: [
      _overviewOverride(
        () => throw const ApiException(AppErrorCode.connectionError),
      ),
    ],
    home: () => const MaintenanceScreen(),
    shows: find.text(pl.retry),
  );

  // --- Settings ---

  a11ySurface(
    'maintenance settings',
    home: () => const MaintenanceSettingsScreen(),
    shows: byLogId('maintenance_settings.type'),
  );

  a11ySurface(
    'maintenance settings, a task muted',
    home: () => const MaintenanceSettingsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('maintenance_settings.mute').first);
      await a11ySettle(tester, const Duration(seconds: 2));
    },
    shows: find.byTooltip(pl.maintenanceUnmute),
  );

  a11ySurface(
    'maintenance settings, no printers',
    overrides: [_overviewOverride(() => const [])],
    home: () => const MaintenanceSettingsScreen(),
    shows: byLogId('maintenance_settings.type'),
  );

  a11ySurface(
    'maintenance settings, types failed',
    overrides: [maintenanceTypesProvider.overrideWith(_FailingTypes.new)],
    home: () => const MaintenanceSettingsScreen(),
    shows: find.text(_unreachable),
  );

  a11ySurface(
    'maintenance settings, create sheet',
    home: () => const MaintenanceSettingsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('maintenance_settings.add_type'));
    },
    shows: find.text(pl.maintenanceAddType),
  );

  a11ySurface(
    'maintenance settings, create sheet with printers picked',
    home: () => const MaintenanceSettingsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('maintenance_settings.add_type'));
      await settle(tester);
      await tester.tap(byLogId('maintenance_type_form.printer').first);
    },
    shows: find.text(pl.maintenanceAssignPrinters),
  );

  a11ySurface(
    'maintenance settings, create sheet with its errors',
    home: () => const MaintenanceSettingsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('maintenance_settings.add_type'));
      await settle(tester);
      await tester.enterText(byLogId('maintenance_type_form.interval'), '0');
      await tester.tap(byLogId('maintenance_type_form.save'));
    },
    shows: find.text(pl.maintenanceIntervalInvalid),
  );

  a11ySurface(
    'maintenance settings, create sheet with the unit menu open',
    home: () => const MaintenanceSettingsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('maintenance_settings.add_type'));
      await settle(tester);
      await tester.tap(byLogId('maintenance_type_form.interval_type'));
    },
    shows: byLogId('maintenance_type_form.interval_type.days'),
  );

  a11ySurface(
    'maintenance settings, edit sheet',
    home: () => const MaintenanceSettingsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('maintenance_settings.type').first);
    },
    shows: find.text(pl.maintenanceEditType),
  );

  a11ySurface(
    'maintenance settings, interval dialog',
    home: () => const MaintenanceSettingsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('maintenance_settings.interval').first);
    },
    shows: find.text(pl.maintenanceResetInterval),
  );

  a11ySurface(
    'maintenance settings, delete confirmation',
    home: () => const MaintenanceSettingsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('maintenance_settings.delete_type').first);
    },
    shows: find.text(pl.maintenanceDeleteTypeTitle),
  );

  a11ySurface(
    'maintenance settings, restore confirmation',
    home: () => const MaintenanceSettingsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('maintenance_settings.restore_defaults'));
    },
    shows: find.text(pl.maintenanceRestoreConfirm),
  );
}

/// What a strip shows for the connection error the failing overrides throw.
final _unreachable = const ApiException(
  AppErrorCode.connectionError,
).localized(pl);

/// Opens the printer cards one by one: each opening moves the next toggle down.
Future<void> _openEveryPrinter(WidgetTester tester) async {
  final count = byLogId('maintenance.printer_toggle').evaluate().length;
  for (var i = 0; i < count; i++) {
    await tester.tap(byLogId('maintenance.printer_toggle').at(i));
    await settle(tester);
  }
}

/// One printer with an overdue task, a task due soon, a muted one and one on a
/// days interval.
final _overview = [
  PrinterMaintenanceOverview(
    printerId: 1,
    printerName: 'X1C-01',
    printerModel: 'X1C',
    totalPrintHours: 412.5,
    dueCount: 1,
    warningCount: 1,
    maintenanceItems: const [
      MaintenanceStatus(
        id: 1,
        printerId: 1,
        maintenanceTypeId: 2,
        maintenanceTypeName: 'Clean Nozzle/Hotend',
        maintenanceTypeIcon: 'Flame',
        intervalHours: 100,
        hoursSinceMaintenance: 112,
        hoursUntilDue: -12,
        isDue: true,
      ),
      MaintenanceStatus(
        id: 2,
        printerId: 1,
        maintenanceTypeId: 1,
        maintenanceTypeName: 'Lubricate Carbon Rods',
        maintenanceTypeIcon: 'Droplet',
        intervalHours: 250,
        hoursSinceMaintenance: 236,
        hoursUntilDue: 14,
        isWarning: true,
      ),
      MaintenanceStatus(
        id: 3,
        printerId: 1,
        maintenanceTypeId: 3,
        maintenanceTypeName: 'Grease Lead Screws',
        maintenanceTypeIcon: 'Wrench',
        enabled: false,
        intervalHours: 500,
        hoursSinceMaintenance: 310,
        hoursUntilDue: 190,
      ),
      MaintenanceStatus(
        id: 4,
        printerId: 1,
        maintenanceTypeId: 4,
        maintenanceTypeName: 'Deep Clean & Inspect',
        maintenanceTypeIcon: 'Search',
        intervalHours: 30,
        intervalType: 'days',
        hoursSinceMaintenance: 5,
        hoursUntilDue: 25,
      ),
    ],
  ),
];

Override _overviewOverride(List<PrinterMaintenanceOverview> Function() list) =>
    maintenanceOverviewProvider.overrideWith(() => _Overview(list));

class _Overview extends MaintenanceOverviewNotifier {
  _Overview(this._list);

  final List<PrinterMaintenanceOverview> Function() _list;

  @override
  Future<List<PrinterMaintenanceOverview>> build() async => _list();
}

class _FailingTypes extends MaintenanceTypesNotifier {
  @override
  Future<List<MaintenanceType>> build() async =>
      throw const ApiException(AppErrorCode.connectionError);
}
