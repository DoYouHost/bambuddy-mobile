import 'package:bambuddy_mobile/core/app_context.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_location.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/locations/printer_locations_providers.dart';
import 'package:bambuddy_mobile/features/locations/printer_locations_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets of the printer locations screen over the
/// demo server: the list, an opened card, both selection modes with their bars,
/// the sort menu, the search miss, the printers without a location, the delete
/// and move dialogs (the move one also with its target menu open), the create
/// and edit sheets with their errors, and the read-only, empty and failed lists.
/// Deliberately not covered: a write in flight (the busy bar), which lasts one
/// request.
void main() {
  // The demo is process-wide; every surface starts from its opening state.

  a11ySurface(
    'locations',
    home: () => const PrinterLocationsScreen(),
    shows: find.text('Workshop'),
  );

  a11ySurface(
    'locations, card opened',
    home: () => const PrinterLocationsScreen(),
    arrange: _openWorkshop,
    shows: byLogId('locations.printer_move'),
  );

  a11ySurface(
    'locations, locations ticked',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.select_mode'));
      await settle(tester);
      await tester.tap(find.text('Workshop'));
    },
    shows: byLogId('locations.delete_selected'),
  );

  a11ySurface(
    'locations, printers ticked',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await _openWorkshop(tester);
      await tester.tap(byLogId('locations.printer_select').first);
    },
    shows: byLogId('locations.move_selected'),
  );

  a11ySurface(
    'locations, sort menu',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.sort'));
    },
    shows: find.text(pl.printerLocationsSortCountDesc),
  );

  a11ySurface(
    'locations, search without a match',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.enterText(byLogId('locations.search'), 'zzz');
    },
    shows: find.text(pl.printerLocationsNoResults),
  );

  a11ySurface(
    'locations, hide empty',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.hide_empty'));
    },
    shows: find.text('Workshop'),
  );

  a11ySurface(
    'locations, printers without a location',
    overrides: [_rosterWithUnfiledPrinters],
    home: () => const PrinterLocationsScreen(),
    shows: find.text(pl.printerLocationsUngrouped(2)),
  );

  a11ySurface(
    'locations, unfiled printers ticked',
    overrides: [_rosterWithUnfiledPrinters],
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.ungrouped_select_all'));
    },
    shows: byLogId('locations.move_selected'),
  );

  a11ySurface(
    'locations, delete confirmation',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.delete').first);
    },
    shows: find.text(pl.printerLocationsDeleteTitle),
  );

  a11ySurface(
    'locations, move dialog',
    home: () => const PrinterLocationsScreen(),
    arrange: _openMoveDialog,
    shows: find.text(pl.printerLocationsMoveTitle),
  );

  a11ySurface(
    'locations, move dialog with the target menu open',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await _openMoveDialog(tester);
      await settle(tester);
      await tester.tap(byLogId('location_move.target'));
    },
    shows: byLogId('location_move.none'),
  );

  a11ySurface(
    'locations, create sheet',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.new'));
    },
    shows: find.text(pl.printerLocationsCreateTitle),
  );

  a11ySurface(
    'locations, create sheet with a colour picked',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.new'));
      await settle(tester);
      await tester.tap(byLogId('location_form.color').first);
    },
    shows: byLogId('location_form.color_clear'),
  );

  a11ySurface(
    'locations, create sheet with an empty name',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.new'));
      await settle(tester);
      await tester.tap(byLogId('location_form.save'));
    },
    shows: find.text(pl.inventoryFieldRequired),
  );

  a11ySurface(
    'locations, create sheet with a name already taken',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.new'));
      await settle(tester);
      await tester.enterText(byLogId('location_form.name'), 'Workshop');
      await tester.tap(byLogId('location_form.save'));
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: find.text(pl.printerLocationsNameTaken),
  );

  a11ySurface(
    'locations, edit sheet',
    home: () => const PrinterLocationsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('locations.edit').first);
    },
    shows: find.text(pl.printerLocationsEditTitle),
  );

  // An API key may read the locations and change nothing: no buttons, a note.
  a11ySurface(
    'locations, read-only session',
    profile: const ServerProfile(
      baseUrl: DemoConfig.baseUrl,
      authMode: AuthMode.apiKey,
    ),
    overrides: [
      // The key cannot reach the demo's routes, so the list is handed over.
      printerLocationsProvider.overrideWith(
        (ref) async => const [
          PrinterLocation(
            id: 1,
            name: 'Workshop',
            icon: 'wrench',
            color: '#f97316',
            printerCount: 1,
          ),
        ],
      ),
      _rosterWithUnfiledPrinters,
    ],
    home: () => const PrinterLocationsScreen(),
    shows: find.text(pl.printerLocationsReadOnly),
  );

  a11ySurface(
    'locations, none yet',
    overrides: [
      printerLocationsProvider.overrideWith((ref) async => const []),
      fixedDashboardOverride(),
    ],
    home: () => const PrinterLocationsScreen(),
    shows: find.text(pl.printerLocationsEmpty),
  );

  a11ySurface(
    'locations, list failed',
    overrides: [
      printerLocationsProvider.overrideWith(
        (ref) async => throw const ApiException(AppErrorCode.connectionError),
      ),
    ],
    home: () => const PrinterLocationsScreen(),
    shows: find.text(pl.retry),
  );
}

Future<void> _openWorkshop(WidgetTester tester) async {
  await tester.tap(find.text('Workshop'));
  await settle(tester);
}

Future<void> _openMoveDialog(WidgetTester tester) async {
  await _openWorkshop(tester);
  await tester.tap(byLogId('locations.printer_move').first);
}

/// The demo's roster plus two printers standing in no location.
final _rosterWithUnfiledPrinters = fixedDashboardOverride(
  DashboardState(
    printers: [
      for (final (id, name, location) in [
        (1, 'Bench', 'Workshop'),
        (2, 'Desk', 'Office'),
        (3, 'Spare', null),
        (4, 'Shelf', null),
      ])
        PrinterWithStatus(
          printer: Printer(
            id: id,
            name: name,
            model: 'X1C',
            location: location,
          ),
          status: PrinterStatus(id: id, connected: true, state: 'IDLE'),
        ),
    ],
  ),
);
