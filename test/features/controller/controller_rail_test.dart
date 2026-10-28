import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_picker.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _phone = Size(844, 390);

SemanticsFinder _semanticsId(String id) =>
    find.semantics.byPredicate((node) => node.identifier == id);

void main() {
  Future<void> pumpOpen(WidgetTester tester) async {
    useLogicalWindow(tester, _phone);
    mockImmersiveChannels(tester, onWindow: (_) {}, onPlatform: (_) {});
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => openController(context, ref),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/controller/:id',
          builder: (_, state) => ControllerScreen(
            printerId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          fixedDashboardOverride(
            DashboardState(
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
        child: plRouterApp(router),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await settle(tester);
  }

  testWidgets('the collapsed rail has no exit: it is in the open panel', (
    tester,
  ) async {
    await pumpOpen(tester);

    expect(byLogId('controller.exit'), findsNothing);
    expect(byLogId('controller.panel_exit'), findsNothing);

    await tester.tap(byLogId('controller.rail_open'));
    await settle(tester);

    expect(byLogId('controller.panel_exit'), findsOneWidget);
  });

  testWidgets('Exit in the open panel leaves the controller', (tester) async {
    await pumpOpen(tester);
    await tester.tap(byLogId('controller.rail_open'));
    await settle(tester);

    await tester.tap(byLogId('controller.panel_exit'));
    await settle(tester);

    expect(find.byType(ControllerScreen), findsNothing);
    expect(find.text('OPEN'), findsOneWidget);
  });

  testWidgets('Back closes the open panel first, and the next one leaves', (
    tester,
  ) async {
    await pumpOpen(tester);
    await tester.tap(byLogId('controller.rail_open'));
    await settle(tester);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(ControllerScreen), findsOneWidget);
    expect(byLogId('controller.panel_exit'), findsNothing);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(ControllerScreen), findsNothing);
  });

  testWidgets('a touch outside the open panel closes it', (tester) async {
    await pumpOpen(tester);
    await tester.tap(byLogId('controller.rail_open'));
    await settle(tester);

    await tester.tapAt(const Offset(800, 200));
    await settle(tester);

    expect(byLogId('controller.panel_exit'), findsNothing);
    expect(find.byType(ControllerScreen), findsOneWidget);
  });

  testWidgets('under the open panel neither the rail nor the screen is read', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpOpen(tester);
    expect(_semanticsId('controller.tab_heat'), findsOneWidget);
    expect(_semanticsId('controller.panel_heat'), findsNothing);

    await tester.tap(byLogId('controller.rail_open'));
    await settle(tester);

    // The panel's row is the only one that names the tab.
    expect(_semanticsId('controller.tab_heat'), findsNothing);
    expect(_semanticsId('controller.panel_heat'), findsOneWidget);
    semantics.dispose();
  });
}
