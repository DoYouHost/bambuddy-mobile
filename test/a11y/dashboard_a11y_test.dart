import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/core/app_context.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/models/discovery.dart';
import 'package:bambuddy_mobile/core/models/printable_object.dart';
import 'package:bambuddy_mobile/core/models/printer_create.dart';
import 'package:bambuddy_mobile/core/models/printer_diagnostic.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/discovery_repository.dart';
import 'package:bambuddy_mobile/data/skip_objects_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/add_printer_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/skip_objects_screen.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/watch/wear_relay_handler.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/dashboard_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dash_kit/dash_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the dashboard screen and everything
/// that opens from it except the printer card: the app bar menu, the drawer, the
/// filter and power sheets, the dialogs, the empty, error and banner states, the
/// skip-objects screen and the add/edit printer form with its scan, diagnostic
/// and save-warning states. The printer card, its states and its sheets are in
/// dashboard_sheets_a11y_test.dart. Not covered: the battery-optimisation dialog
/// (built only when `Platform.isAndroid`, which a host test cannot fake) and the
/// screens the menu, the drawer and the card navigate to (camera, file manager,
/// wall, controller, notification settings, ...), which belong to their own
/// feature's file.
void main() {
  a11ySurface(
    'dashboard, demo fleet',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    shows: find.text('X1 Carbon'),
  );

  a11ySurface(
    'dashboard, a section folded',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('dashboard.group').last),
    shows: find.text('X1 Carbon'),
  );

  a11ySurface(
    'dashboard, drawer',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: _openDrawer,
    shows: byLogId('drawer.about'),
  );

  a11ySurface(
    'dashboard, app bar menu',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('dashboard.menu')),
    shows: byLogId('dashboard.wall_mode'),
  );

  a11ySurface(
    'dashboard, notifications sheet',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('dashboard.menu'));
      await a11yTap(tester, byLogId('dashboard.notifications_menu'));
    },
    shows: byLogId('notifications_menu.background'),
  );

  a11ySurface(
    'dashboard, filter sheet',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('dashboard.filters')),
    shows: byLogId('sheet.dashboard_filters'),
  );

  // A chip selected, "hide offline" on and the location menu open: the sheet
  // with its Clear button showing and the combo's own popup over it.
  a11ySurface(
    'dashboard, filter sheet, location menu',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('dashboard.filters'));
      await a11yTap(tester, find.text(pl.statusPrinting).last);
      await a11yTap(tester, byLogId('dashboard_filters.location'));
    },
    shows: byLogId('dashboard_filters.location_option'),
  );

  // A status no printer is in: the sheet's Clear button shows, the list behind
  // it explains why it is empty.
  a11ySurface(
    'dashboard, filters match nothing',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) async {
      await a11yTap(tester, byLogId('dashboard.filters'));
      await a11yTap(tester, find.text(pl.statusErrorFilter).last);
    },
    shows: find.text(pl.noPrintersMatchFilters),
  );

  // A server with a label shows it under the title and in the drawer header.
  // The demo profile with a label, so the demo backend still answers.
  a11ySurface(
    'dashboard, labelled server',
    demo: false,
    overrides: [..._dashboard, serverProfileOverride(_labelled)],
    home: () => const DashboardScreen(),
    arrange: _openDrawer,
    shows: find.text(_labelled.label!),
  );

  a11ySurface(
    'dashboard, power sheet',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('dashboard.power')),
    shows: find.text(pl.powerBreakdownTitle),
  );

  a11ySurface(
    'dashboard, change server dialog',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) async {
      await _openDrawer(tester);
      await a11yTap(tester, byLogId('drawer.change_server'));
    },
    shows: find.text(pl.changeServerQuestion),
  );

  // The flag is raised on disk, as another isolate raises it, and found by the
  // next resume: the pumped preferences were created empty by the harness.
  a11ySurface(
    'dashboard, sign-in required dialog',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) async {
      SharedPreferences.setMockInitialValues({'sign_in_required': true});
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await a11ySettle(tester, const Duration(seconds: 1));
    },
    shows: find.text(pl.signInRequiredTitle),
  );

  a11ySurface(
    'dashboard, search finds nothing',
    overrides: _dashboard,
    home: () => const DashboardScreen(),
    arrange: (tester) async {
      await tester.enterText(
        find.descendant(
          of: byLogId('dashboard.search'),
          matching: find.byType(TextField),
        ),
        'zzz',
      );
      await a11ySettle(tester, const Duration(milliseconds: 500));
    },
    shows: find.text(pl.noSearchResults('zzz')),
  );

  a11ySurface(
    'dashboard, no printers',
    overrides: [..._dashboard, fixedDashboardOverride(_empty)],
    home: () => const DashboardScreen(),
    shows: find.text(pl.noPrinters),
  );

  a11ySurface(
    'dashboard, server unreachable',
    overrides: [
      ..._dashboard,
      fixedDashboardOverride(
        const DashboardState(
          error: NetworkException(AppErrorCode.serverUnreachable),
        ),
      ),
    ],
    home: () => const _WarmedDashboard(),
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'dashboard, loading',
    overrides: [..._dashboard, fixedDashboardOverride(const DashboardState())],
    home: () => const _WarmedDashboard(),
    shows: find.byType(DashLoading),
  );

  // The last poll failed: the banner sits above the last roster.
  a11ySurface(
    'dashboard, stale banner',
    overrides: [
      ..._dashboard,
      fixedDashboardOverride(
        const DashboardState(
          printers: [PrinterWithStatus(printer: Printer(id: 1, name: 'X1C'))],
          error: NetworkException(AppErrorCode.serverUnreachable),
        ),
      ),
    ],
    home: () => const DashboardScreen(),
    shows: find.text(pl.serverUnreachableStale),
  );

  a11ySurface(
    'dashboard, socket reconnecting banner',
    overrides: [
      ..._dashboard,
      wsConnectionStateProvider.overrideWith(
        (ref) => Stream.value(WsConnectionState.waitingRetry),
      ),
    ],
    home: () => const DashboardScreen(),
    shows: find.text(pl.wsReconnecting),
  );

  // --- skip objects (demo printer 1 prints a four-object plate) ---------------

  a11ySurface(
    'skip objects',
    home: _skipObjects,
    shows: byLogId('skip_objects.object_tile'),
  );

  // A tile tapped: the confirm bar with its count and Skip button appears.
  a11ySurface(
    'skip objects, one selected',
    home: _skipObjects,
    arrange: (tester) =>
        a11yTap(tester, byLogId('skip_objects.object_tile').first),
    shows: byLogId('skip_objects.skip'),
  );

  a11ySurface(
    'skip objects, confirm dialog',
    home: _skipObjects,
    arrange: (tester) async {
      await a11yTap(tester, byLogId('skip_objects.object_tile').first);
      await a11yTap(tester, byLogId('skip_objects.skip'));
    },
    shows: byLogId('skip_objects.confirm'),
  );

  // Wide window: the plate and the list sit side by side, a different tree.
  a11ySurface(
    'skip objects, landscape',
    window: landscapeRedmi,
    home: _skipObjects,
    arrange: (tester) =>
        a11yTap(tester, byLogId('skip_objects.object_tile').first),
    shows: byLogId('skip_objects.skip'),
  );

  a11ySurface(
    'skip objects, nothing to skip',
    home: () => const SkipObjectsScreen(printerId: 2, printerName: 'P1S'),
    shows: byLogId('skip_objects.reload'),
  );

  // First layer still printing: the warning banner, and every tile locked.
  a11ySurface(
    'skip objects, first layer warning',
    overrides: [printerStatusesProvider.overrideWith(_FirstLayerStatuses.new)],
    home: _skipObjects,
    shows: find.text(pl.skipObjectsWaitForLayer(1)),
  );

  a11ySurface(
    'skip objects, load failed',
    overrides: [
      skipObjectsRepositoryProvider.overrideWith(
        (ref) => _FailingSkipObjects(ref.watch(apiClientProvider).dio),
      ),
    ],
    home: _skipObjects,
    shows: find.text(pl.retry),
  );

  // --- add and edit printer ----------------------------------------------------

  a11ySurface(
    'add printer',
    home: () => const AddPrinterScreen(),
    shows: byLogId('add_printer.submit'),
  );

  // Required-field messages under every empty field.
  a11ySurface(
    'add printer, validation errors',
    home: () => const AddPrinterScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('add_printer.submit')),
    shows: find.text(pl.addPrinterRequiredField),
  );

  a11ySurface(
    'add printer, access code revealed',
    home: () => const AddPrinterScreen(),
    arrange: (tester) async {
      await _fillForm(tester);
      await a11yTap(tester, byLogId('add_printer.reveal_access_code'));
    },
    shows: byLogId('add_printer.reveal_access_code'),
  );

  a11ySurface(
    'add printer, model menu',
    home: () => const AddPrinterScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('add_printer.model')),
    shows: byLogId('add_printer.model_option'),
  );

  a11ySurface(
    'add printer, location menu',
    home: () => const AddPrinterScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('add_printer.location')),
    shows: byLogId('add_printer.location_option'),
  );

  // The server refused the create: its reason in red above the button.
  a11ySurface(
    'add printer, create refused',
    overrides: [_stubPrinters(createFails: true)],
    home: () => const AddPrinterScreen(),
    arrange: (tester) async {
      await _fillForm(tester);
      await a11yTap(tester, byLogId('add_printer.submit'));
    },
    shows: find.text(pl.addPrinterErrDuplicate),
  );

  a11ySurface(
    'add printer, connection check result',
    overrides: [_stubPrinters()],
    home: () => const AddPrinterScreen(),
    arrange: (tester) async {
      await _fillForm(tester);
      await a11yTap(tester, byLogId('add_printer.diagnose'));
    },
    shows: find.text(pl.diagOverallProblems),
  );

  a11ySurface(
    'add printer, connection check needs an address',
    home: () => const AddPrinterScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('add_printer.diagnose')),
    shows: find.text(pl.addPrinterRequiredField),
  );

  // Native install: detected subnets, scan by SSDP.
  a11ySurface(
    'add printer, network scan',
    overrides: [_discovery(isDocker: false, subnets: _subnets)],
    home: () => const AddPrinterScreen(),
    shows: byLogId('add_printer.scan_network'),
  );

  a11ySurface(
    'add printer, subnet menu',
    overrides: [_discovery(isDocker: false, subnets: _subnets)],
    home: () => const AddPrinterScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('add_printer.subnet')),
    shows: byLogId('add_printer.subnet_custom_option'),
  );

  a11ySurface(
    'add printer, discovered printers',
    overrides: [_discovery(isDocker: false, subnets: _subnets, found: _found)],
    home: () => const AddPrinterScreen(),
    arrange: _scan,
    shows: byLogId('add_printer.discovered'),
  );

  a11ySurface(
    'add printer, scan found nothing',
    overrides: [_discovery(isDocker: false, subnets: _subnets)],
    home: () => const AddPrinterScreen(),
    arrange: _scan,
    shows: find.text(pl.addPrinterScanNoResults),
  );

  a11ySurface(
    'add printer, scan failed',
    overrides: [
      _discovery(isDocker: false, subnets: _subnets, scanFails: true),
    ],
    home: () => const AddPrinterScreen(),
    arrange: _scan,
    shows: find.text(pl.addPrinterScanError),
  );

  // Docker server: no detected subnet, so the CIDR field is the only input.
  a11ySurface(
    'add printer, subnet scan needs a CIDR',
    overrides: [_discovery(isDocker: true, subnets: const [])],
    home: () => const AddPrinterScreen(),
    arrange: (tester) => a11yTap(tester, byLogId('add_printer.scan_network')),
    shows: byLogId('add_printer.custom_subnet'),
  );

  a11ySurface(
    'add printer, subnet scan results',
    overrides: [_discovery(isDocker: true, subnets: const [], found: _found)],
    home: () => const AddPrinterScreen(),
    arrange: (tester) async {
      await tester.enterText(
        find.descendant(
          of: byLogId('add_printer.custom_subnet'),
          matching: find.byType(TextField),
        ),
        '192.168.4.0/24',
      );
      await _scan(tester);
    },
    shows: byLogId('add_printer.discovered'),
  );

  a11ySurface(
    'edit printer',
    home: () => AddPrinterScreen(printer: _editedPrinter),
    shows: byLogId('add_printer.maintenance'),
  );

  // A failed connection check before the save: the check rows and the
  // Back / Save anyway pair replace the submit button.
  a11ySurface(
    'edit printer, connection check failed',
    overrides: [_stubPrinters()],
    home: () => AddPrinterScreen(printer: _editedPrinter),
    arrange: (tester) => a11yTap(tester, byLogId('add_printer.submit')),
    shows: byLogId('add_printer.preflight_save_anyway'),
  );

  a11ySurface(
    'edit printer, wear rate rejected',
    home: () => AddPrinterScreen(printer: _editedPrinter),
    arrange: (tester) async {
      await tester.enterText(find.widgetWithText(TextFormField, '0.25'), 'abc');
      await a11yTap(tester, byLogId('add_printer.submit'));
    },
    shows: find.text(pl.editPrinterWearCostInvalid),
  );
}

/// What the dashboard touches on its first frame: the background service
/// (a platform channel) and the notification plugin.
final List<Override> _dashboard = [
  ...a11yPlatformOverrides,
  wearRelayHandlerProvider.overrideWithValue(_InertWearRelay()),
];

const _empty = DashboardState(printers: []);

Future<void> _openDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await a11ySettle(tester, const Duration(milliseconds: 600));
}

/// The watch relay without the Data Layer channel underneath; a resume starts
/// it and a pause stops it.
class _InertWearRelay extends WearRelayHandler {
  _InertWearRelay() : super(watch: WatchConnectivity(), dio: () => null);

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

/// The dashboard with the API client already built. The empty-roster body
/// listens to `ServerReachability`, and the first client built (by the drawer
/// button, earlier in the same frame) resets it, which marks that listener
/// dirty mid-build. The running app builds the client long before the screen.
class _WarmedDashboard extends ConsumerWidget {
  const _WarmedDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authServiceProvider);
    return const DashboardScreen();
  }
}

Widget _skipObjects() =>
    const SkipObjectsScreen(printerId: 1, printerName: 'X1 Carbon');

/// The first layer: the screen holds every selection back until the second.
class _FirstLayerStatuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => {
    1: const PrinterStatus(id: 1, layerNum: 1),
  };
}

class _FailingSkipObjects extends SkipObjectsRepository {
  _FailingSkipObjects(super.dio);

  @override
  Future<PrintableObjects> fetchObjects(
    int printerId, {
    bool reload = false,
  }) async => throw const NetworkException(AppErrorCode.serverUnreachable);
}

/// The demo printer 1 as the edit form opens it, with the wear-rate field the
/// server 1.2.6 sends.
final _editedPrinter = Printer.fromJson(const {
  'id': 1,
  'name': 'X1 Carbon',
  'model': 'X1C',
  'ip_address': '192.168.4.21',
  'serial_number': '01P00A390800000',
  'location': 'Workshop',
  'is_active': true,
  'auto_archive': true,
  'wear_cost_per_hour': 0.25,
});

/// Name, address, serial and access code, in the order the form lays them out.
Future<void> _fillForm(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  for (final (i, text) in [
    'Bench X1',
    '192.168.4.30',
    '01P00A111111111',
    '12345678',
  ].indexed) {
    await tester.enterText(fields.at(i), text);
  }
  await a11ySettle(tester, const Duration(milliseconds: 300));
}

/// The scan button, then the ten seconds the SSDP poll takes to finish.
Future<void> _scan(WidgetTester tester) async {
  await tester.tap(byLogId('add_printer.scan_network'));
  await a11ySettle(tester, const Duration(seconds: 13));
}

const _subnets = ['192.168.1.0/24', '10.0.0.0/24'];

const _found = [
  DiscoveredPrinter(
    serial: '01P00A390800009',
    name: 'Garage X1C',
    ipAddress: '192.168.1.40',
    model: 'X1C',
  ),
];

Override _discovery({
  required bool isDocker,
  required List<String> subnets,
  List<DiscoveredPrinter> found = const [],
  bool scanFails = false,
}) => discoveryRepositoryProvider.overrideWith(
  (ref) => _StubDiscovery(
    ref.watch(apiClientProvider).dio,
    DiscoveryInfo(isDocker: isDocker, subnets: subnets),
    found,
    scanFails,
  ),
);

class _StubDiscovery extends DiscoveryRepository {
  _StubDiscovery(super.dio, this._info, this._found, this._scanFails);

  final DiscoveryInfo _info;
  final List<DiscoveredPrinter> _found;
  final bool _scanFails;

  @override
  Future<DiscoveryInfo> info() async => _info;

  @override
  Future<ScanStatus> startScan(String subnet, {double timeout = 1.0}) async {
    if (_scanFails) {
      throw const NetworkException(AppErrorCode.serverUnreachable);
    }
    return const ScanStatus(running: true, scanned: 0, total: 254);
  }

  @override
  Future<ScanStatus> scanStatus() async =>
      const ScanStatus(running: false, scanned: 254, total: 254);

  @override
  Future<void> startSsdp({double duration = 10.0}) async {
    if (_scanFails) {
      throw const NetworkException(AppErrorCode.serverUnreachable);
    }
  }

  @override
  Future<void> stopSsdp() async {}

  @override
  Future<List<DiscoveredPrinter>> discoveredPrinters() async => _found;
}

/// Printers repository whose connection check reports one failure, one warning
/// and one pass, and whose create is refused when [createFails]. Everything else
/// is the demo's.
Override _stubPrinters({bool createFails = false}) =>
    printersRepositoryProvider.overrideWith(
      (ref) => _StubPrinters(ref.watch(apiClientProvider).dio, createFails),
    );

class _StubPrinters extends PrintersRepository {
  _StubPrinters(super.dio, this._createFails);

  final bool _createFails;

  @override
  Future<PrinterDiagnosticResult> diagnose({
    required String ipAddress,
    String? serialNumber,
    String? accessCode,
  }) async => PrinterDiagnosticResult(
    ipAddress: ipAddress,
    overall: 'problems',
    checks: const [
      DiagnosticCheck(id: 'port_mqtt', status: 'fail'),
      DiagnosticCheck(id: 'network_mode', status: 'warn'),
      DiagnosticCheck(id: 'subnet', status: 'pass'),
      DiagnosticCheck(id: 'developer_mode', status: 'skip'),
    ],
  );

  @override
  Future<Printer> createPrinter(PrinterCreate data) async {
    if (_createFails) {
      throw const CreatePrinterException(CreatePrinterFailure.duplicateSerial);
    }
    return super.createPrinter(data);
  }
}

/// The demo profile with a label, so the demo backend still answers.
const _labelled = ServerProfile(
  baseUrl: DemoConfig.baseUrl,
  authMode: AuthMode.none,
  label: 'Workshop server',
);
