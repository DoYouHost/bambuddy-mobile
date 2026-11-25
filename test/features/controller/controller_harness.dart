import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_prints.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The printer every controller-screen test opens: id 1, idle and reachable.
const controllerTestPrinterId = 1;
const controllerTestPrinterName = 'X1C Warsztat';

/// The controller screen for printer 1 on a landscape phone, with the platform
/// calls it makes answered and nothing else on the network. [overrides] come
/// last, so a test replaces any of these.
Future<void> pumpControllerScreen(
  WidgetTester tester, {
  String? model = 'P1S',
  Size size = landscapeRedmi,
  List<Override> overrides = const [],
}) async {
  useLogicalWindow(tester, size);
  mockImmersiveChannels(tester);
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      retry: neverRetry,
      overrides: layerOverrides([
        sharedPreferencesProvider.overrideWithValue(sp),
        fixedDashboardOverride(
          singlePrinterDashboard(name: controllerTestPrinterName, model: model),
        ),
        inertStatusesOverride,
        ...inertDashboardPollOverrides,
      ], overrides),
      child: plApp(const ControllerScreen(printerId: controllerTestPrinterId)),
    ),
  );
  await settle(tester);
}

/// A dashboard holding printer [id] alone, idle and reachable unless [status]
/// says otherwise.
DashboardState singlePrinterDashboard({
  PrinterStatus? status,
  String name = 'P',
  String? model,
  int id = controllerTestPrinterId,
}) => DashboardState(
  printers: [
    PrinterWithStatus(
      printer: Printer(id: id, name: name, model: model),
      status: status ?? PrinterStatus(id: id, connected: true, state: 'IDLE'),
    ),
  ],
);

/// [child] scaled the way the controller screen scales a tab's body.
Widget scaledControllerBody(Widget child, {bool reflows = false}) => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(16),
    child: ScaleToFit(reflows: reflows, child: child),
  ),
);

/// [home] on a landscape phone with one printer ([status], [name], [model]) and
/// no server profile, for a test of one tab or panel rather than the whole
/// screen. [prefs] seeds SharedPreferences; [overrides] come last, so a test
/// replaces any of the base ones.
Future<void> pumpControllerPanel(
  WidgetTester tester,
  Widget home, {
  PrinterStatus? status,
  String name = 'P',
  String? model,
  Size size = const Size(844, 390),
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
}) async {
  useLogicalWindow(tester, size);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  await pumpPhone(
    tester,
    home,
    overrides: layerOverrides([
      sharedPreferencesProvider.overrideWithValue(sp),
      noServerProfileOverride,
      fixedDashboardOverride(
        singlePrinterDashboard(status: status, name: name, model: model),
      ),
      inertStatusesOverride,
    ], overrides),
  );
  await tester.pump();
}

/// Opens the Prints tab on [view].
Future<void> openPrintsView(
  WidgetTester tester,
  ControllerPrintsView view,
) async {
  // The tabs scroll where a short phone or a large font leaves them no room.
  await tester.ensureVisible(byLogId(ControllerTab.prints.logId));
  await settle(tester);
  await tester.tap(byLogId(ControllerTab.prints.logId));
  await settle(tester);
  await tester.tap(byLogId(view.logId));
  await settle(tester);
}
