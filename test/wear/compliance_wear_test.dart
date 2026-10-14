import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/wear/screens/wear_printer_control_screen.dart';
import 'package:bambuddy_mobile/wear/screens/wear_printer_list_screen.dart';
import 'package:bambuddy_mobile/wear/screens/wear_settings_screen.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_theme.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Wear OS app quality rows a widget test can check (docs/play-compliance.md).

class _Transport implements WearTransport {
  @override
  Future<WearFleet> getFleet() async => WearFleet(
    printers: [
      PrinterWithStatus(
        printer: const Printer(id: 7, name: 'X1C'),
        status: const PrinterStatus(
          id: 7,
          connected: true,
          state: 'RUNNING',
          progress: 40,
          remainingTime: 60,
        ),
      ),
      PrinterWithStatus(
        printer: const Printer(id: 8, name: 'P1S'),
        status: const PrinterStatus(id: 8, connected: true, state: 'IDLE'),
      ),
    ],
    queuePending: 2,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

void main() {
  final screens = <String, Widget>{
    'printer list': const Scaffold(body: WearPrinterListBody()),
    'control screen': const WearPrinterControlScreen(printerId: 7),
    'settings': const WearSettingsScreen(),
  };

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    testWidgets('$name: every touch target is at least 48 dp (WO-V2)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWear(
        tester,
        screen,
        face: wearFaceLarge,
        overrides: [
          noServerProfileOverride,
          wearTransportProvider.overrideWith(
            (ref) => HybridWearTransport(relay: _Transport()),
          ),
        ],
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }

  test('the watch draws on black (WO-V13)', () {
    final theme = wearTheme();
    expect(theme.scaffoldBackgroundColor, Colors.black);
    expect(theme.colorScheme.surface, Colors.black);
  });
}
