import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/printer_locations_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/locations/printer_locations_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

const _path = '/api/v1/printer-locations/';

final _locations = <Map<String, dynamic>>[
  {
    'id': 1,
    'name': 'Workshop',
    'icon': 'wrench',
    'color': '#f97316',
    'printer_count': 2,
  },
  {'id': 2, 'name': 'Attic', 'icon': null, 'color': null, 'printer_count': 0},
  {'id': null, 'name': 'Office', 'printer_count': 1},
];

PrinterWithStatus _printer(int id, String name, String? location) =>
    PrinterWithStatus(
      printer: Printer(id: id, name: name, model: 'X1C', location: location),
      status: PrinterStatus(id: id, connected: true, state: 'IDLE'),
    );

final _farm = [
  _printer(1, 'Bench', 'Workshop'),
  _printer(2, 'Bench 2', ' Workshop '),
  _printer(3, 'Desk', 'Office'),
  _printer(4, 'Spare', null),
];

class _FixedDashboard extends DashboardNotifier {
  @override
  DashboardState build() => DashboardState(printers: _farm);

  @override
  Future<void> refresh() async {}
}

void main() {
  late RequestLog sent;
  late DioAdapter adapter;

  Future<void> pumpScreen(
    WidgetTester tester, {
    AuthMode authMode = AuthMode.none,
    CurrentUser? user,
  }) async {
    final dio = testDio();
    adapter = mockServer(dio);
    sent = captureRequests(dio);
    adapter.onGet(_path, (s) => s.reply(200, _locations));
    await pumpPhone(
      tester,
      const PrinterLocationsScreen(),
      overrides: [
        fakeServerProfileOverride(authMode: authMode),
        printerLocationsRepositoryProvider.overrideWithValue(
          PrinterLocationsRepository(dio),
        ),
        dashboardProvider.overrideWith(_FixedDashboard.new),
        inertStatusesOverride,
        if (user != null) currentUserOverride(user),
      ],
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  testWidgets('lists the locations with their counts and the printers '
      'that have none', (tester) async {
    await pumpScreen(tester);
    final l = l10n(tester);

    expect(find.text('Workshop'), findsOneWidget);
    expect(find.text(l.printerLocationsPrinterCount(2)), findsOneWidget);
    // Natural order: Attic, Office, Workshop.
    expect(
      tester.getTopLeft(find.text('Attic')).dy,
      lessThan(tester.getTopLeft(find.text('Workshop')).dy),
    );
    // A trailing space on a stored location still files the printer.
    expect(find.text(l.printerLocationsSubtitle(3, 1)), findsOneWidget);
    expect(find.text(l.printerLocationsUngrouped(1)), findsOneWidget);
    expect(find.text('Spare'), findsOneWidget);
  });

  testWidgets('a card opens onto its printers, and an empty one says so', (
    tester,
  ) async {
    await pumpScreen(tester);
    final l = l10n(tester);

    await tester.tap(find.text('Workshop'));
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('Bench 2'), findsOneWidget);

    await tester.tap(find.text('Attic'));
    await tester.pumpAndSettle();
    expect(find.text(l.printerLocationsNoPrinters), findsOneWidget);
    // One card open at a time, as on the web page.
    expect(find.text('Bench'), findsNothing);
  });

  testWidgets('search narrows the list and says when nothing is left', (
    tester,
  ) async {
    await pumpScreen(tester);
    final l = l10n(tester);

    await tester.enterText(byLogId('locations.search'), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Workshop'), findsNothing);
    expect(find.text(l.printerLocationsNoResults), findsNothing);
    // The printers without a location stay, so the list is not empty.
    expect(find.text('Spare'), findsOneWidget);
  });

  testWidgets('hide empty drops the location with no printer', (tester) async {
    await pumpScreen(tester);

    await tester.tap(byLogId('locations.hide_empty'));
    await tester.pumpAndSettle();

    expect(find.text('Attic'), findsNothing);
    expect(find.text('Workshop'), findsOneWidget);
  });

  testWidgets('moving a ticked printer posts its id and the chosen '
      'location', (tester) async {
    await pumpScreen(tester);
    adapter.onPost(
      '${_path}assign',
      (s) => s.reply(200, {'moved': 1}),
      data: {
        'printer_ids': [4],
        'location': 'Office',
      },
    );

    await tester.tap(byLogId('locations.printer_select'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('locations.move_selected'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('location_move.target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office').last);
    await tester.pumpAndSettle();
    await tester.tap(byLogId('location_move.confirm'));
    await tester.pumpAndSettle();

    final posts = sent.requests.where((r) => r.method == 'POST').toList();
    expect(posts.single.path, '${_path}assign');
    expect(posts.single.data, {
      'printer_ids': [4],
      'location': 'Office',
    });
  });

  testWidgets('taking a printer out of a location sends a null location', (
    tester,
  ) async {
    await pumpScreen(tester);
    adapter.onPost(
      '${_path}assign',
      (s) => s.reply(200, {'moved': 1}),
      data: {
        'printer_ids': [3],
        'location': null,
      },
    );

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('locations.printer_remove'));
    await tester.pumpAndSettle();

    final posts = sent.requests.where((r) => r.method == 'POST').toList();
    expect(posts.single.data, {
      'printer_ids': [3],
      'location': null,
    });
  });

  testWidgets('deleting asks first, then sends the name', (tester) async {
    await pumpScreen(tester);
    adapter.onPost(
      '${_path}delete',
      (s) => s.reply(200, {'deleted': 1, 'printers_ungrouped': 0}),
      data: {
        'names': ['Attic'],
      },
    );

    await tester.tap(byLogId('locations.delete').at(0));
    await tester.pumpAndSettle();
    expect(sent.requests.where((r) => r.method == 'POST'), isEmpty);

    await tester.tap(byLogId('locations.delete_confirm.confirm'));
    await tester.pumpAndSettle();

    final posts = sent.requests.where((r) => r.method == 'POST').toList();
    expect(posts.single.data, {
      'names': ['Attic'],
    });
  });

  testWidgets('an API-key session can read the list and change nothing', (
    tester,
  ) async {
    await pumpScreen(tester, authMode: AuthMode.apiKey);
    final l = l10n(tester);

    expect(find.text('Workshop'), findsOneWidget);
    expect(find.text(l.printerLocationsReadOnly), findsOneWidget);
    expect(byLogId('locations.new'), findsNothing);
    expect(byLogId('locations.edit'), findsNothing);
    expect(byLogId('locations.delete'), findsNothing);
    expect(byLogId('locations.select_mode'), findsNothing);
  });

  testWidgets('a user without printers:update sees no controls', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      user: const CurrentUser(
        id: 2,
        username: 'viewer',
        isAdmin: false,
        permissions: {'printers:read'},
      ),
    );

    expect(find.text('Workshop'), findsOneWidget);
    expect(byLogId('locations.new'), findsNothing);
    expect(byLogId('locations.printer_select'), findsNothing);
  });

  testWidgets('a name already taken is shown on the name field', (
    tester,
  ) async {
    await pumpScreen(tester);
    final l = l10n(tester);
    adapter.onPost(
      _path,
      (s) =>
          s.reply(409, {'detail': 'A location with this name already exists'}),
      data: {'name': 'Attic', 'icon': null, 'color': null},
    );

    await tester.tap(byLogId('locations.new'));
    await tester.pumpAndSettle();
    await tester.enterText(byLogId('location_form.name'), 'Attic');
    await tester.tap(byLogId('location_form.save'));
    await tester.pumpAndSettle();

    expect(find.text(l.printerLocationsNameTaken), findsOneWidget);
  });

  testWidgets('moving one printer from its row keeps the other ticks', (
    tester,
  ) async {
    await pumpScreen(tester);
    adapter.onPost(
      '${_path}assign',
      (s) => s.reply(200, {'moved': 1}),
      data: {
        'printer_ids': [3],
        'location': 'Attic',
      },
    );

    // Spare (id 4) is ticked; Desk (id 3) is then moved on its own.
    await tester.tap(byLogId('locations.printer_select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('locations.printer_move').first);
    await tester.pumpAndSettle();
    await tester.tap(byLogId('location_move.target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attic').last);
    await tester.pumpAndSettle();
    await tester.tap(byLogId('location_move.confirm'));
    await tester.pumpAndSettle();

    expect(
      sent.requests.where((r) => r.method == 'POST').single.data,
      containsPair('printer_ids', [3]),
    );
    expect(byLogId('locations.move_selected'), findsOneWidget);
  });

  testWidgets('a printer taken out of its location is no longer ticked', (
    tester,
  ) async {
    await pumpScreen(tester);
    adapter.onPost(
      '${_path}assign',
      (s) => s.reply(200, {'moved': 1}),
      data: {
        'printer_ids': [3],
        'location': null,
      },
    );

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('locations.printer_select'));
    await tester.pumpAndSettle();
    expect(byLogId('locations.move_selected'), findsOneWidget);

    await tester.tap(byLogId('locations.printer_remove'));
    await tester.pumpAndSettle();

    expect(byLogId('locations.move_selected'), findsNothing);
  });

  testWidgets('a server that answered 404 to the listing offers no writes', (
    tester,
  ) async {
    final dio = testDio();
    mockServer(dio).onGet(_path, (s) => s.reply(404, {'detail': 'Not Found'}));
    await pumpPhone(
      tester,
      const PrinterLocationsScreen(),
      overrides: [
        fakeServerProfileOverride(),
        printerLocationsRepositoryProvider.overrideWithValue(
          PrinterLocationsRepository(dio),
        ),
        dashboardProvider.overrideWith(_FixedDashboard.new),
        inertStatusesOverride,
      ],
    );
    await tester.pumpAndSettle();

    expect(byLogId('locations.new'), findsNothing);
  });
}
