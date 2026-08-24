import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/screens/wear_printer_control_screen.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

WearFleet _fleet({required bool connected, required bool awaiting}) => WearFleet(
      printers: [
        PrinterWithStatus(
          printer: const Printer(id: 7, name: 'X1C'),
          status: PrinterStatus(
            id: 7,
            connected: connected,
            state: connected ? 'FINISH' : null,
            awaitingPlateClear: awaiting,
          ),
        ),
      ],
    );

/// The watch's plate-clear button, on the printer the gate is normally raised
/// on: one Auto Power Off has already switched off. The server keeps the gate
/// itself and takes the acknowledgement without an MQTT client (#2864), so the
/// watch is a perfectly good place to release it — the trap is the watch's own
/// offline handling, which takes the faults off screen for good reasons that do
/// not apply here.
Future<FakeWearTransport> _pumpControl(
  WidgetTester tester, {
  bool connected = false,
  bool awaiting = true,
  bool require = true,
}) async {
  final transport =
      FakeWearTransport(fleet: _fleet(connected: connected, awaiting: awaiting));
  await pumpWear(
    tester,
    const WearPrinterControlScreen(printerId: 7),
    overrides: [
      noServerProfileOverride,
      wearTransportProvider.overrideWith(
        (ref) => HybridWearTransport(relay: transport),
      ),
      requirePlateClearProvider.overrideWith((ref) async => require),
    ],
  );
  return transport;
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  testWidgets('an offline printer still offers the acknowledgement',
      (tester) async {
    final transport = await _pumpControl(tester);

    expect(find.text('Offline'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Zwolnij płytę'));
    await tester.pumpAndSettle();

    expect(transport.commands, ['clearPlate:7']);
  });

  testWidgets('no gate up, no button', (tester) async {
    await _pumpControl(tester, awaiting: false);

    expect(find.widgetWithText(FilledButton, 'Zwolnij płytę'), findsNothing);
  });

  testWidgets('the scheduler not requiring it takes the button away',
      (tester) async {
    await _pumpControl(tester, require: false);

    expect(find.widgetWithText(FilledButton, 'Zwolnij płytę'), findsNothing);
  });
}
