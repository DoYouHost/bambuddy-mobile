import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_prints.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        fixedDashboardOverride(
          DashboardState(
            printers: [
              PrinterWithStatus(
                printer: Printer(
                  id: controllerTestPrinterId,
                  name: controllerTestPrinterName,
                  model: model,
                ),
                status: const PrinterStatus(
                  id: controllerTestPrinterId,
                  connected: true,
                  state: 'IDLE',
                ),
              ),
            ],
          ),
        ),
        inertStatusesOverride,
        inertSmartPlugsOverride,
        ...overrides,
      ],
      child: plApp(const ControllerScreen(printerId: controllerTestPrinterId)),
    ),
  );
  await settle(tester);
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
