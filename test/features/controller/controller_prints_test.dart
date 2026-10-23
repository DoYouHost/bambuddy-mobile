import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_files.dart';
import 'package:bambuddy_mobile/features/controller/controller_prints.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The Prints tab's rail: which view it shows, and that the choice outlives a
/// visit to another tab, as the library's folder does.
void main() {
  Future<void> pump(WidgetTester tester) async {
    useLogicalWindow(tester, landscapeRedmi);
    mockImmersiveChannels(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          noServerProfileOverride,
          fixedDashboardOverride(
            const DashboardState(
              printers: [
                PrinterWithStatus(
                  printer: Printer(id: 1, name: 'X1C Warsztat', model: 'X1C'),
                  status: PrinterStatus(id: 1, connected: true, state: 'IDLE'),
                ),
              ],
            ),
          ),
          inertStatusesOverride,
          inertSmartPlugsOverride,
        ],
        child: plApp(const ControllerScreen(printerId: 1)),
      ),
    );
    await settle(tester);
    await tester.tap(byLogId('controller.tab_prints'));
    await settle(tester);
  }

  testWidgets('the tab opens on Files, and the rail switches the view', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(ControllerFiles), findsOneWidget);
    for (final view in ControllerPrintsView.values) {
      expect(byLogId(view.logId), findsOneWidget);
    }

    await tester.tap(byLogId(ControllerPrintsView.queue.logId));
    await settle(tester);

    expect(find.byType(ControllerFiles), findsNothing);
  });

  testWidgets('another tab and back keeps the chosen view', (tester) async {
    await pump(tester);
    await tester.tap(byLogId(ControllerPrintsView.archive.logId));
    await settle(tester);

    await tester.tap(byLogId('controller.tab_heat'));
    await settle(tester);
    await tester.tap(byLogId('controller.tab_prints'));
    await settle(tester);

    expect(find.byType(ControllerFiles), findsNothing);
    final archive = tester.widget<ControllerPrints>(
      find.byType(ControllerPrints),
    );
    expect(archive.view, ControllerPrintsView.archive);
  });
}
