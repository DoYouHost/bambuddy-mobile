import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_saver.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

void main() {
  // The saver re-themes itself dark whatever the app runs in; it must keep
  // the brand the user chose rather than fall back to the green one.
  testWidgets('the saver keeps the chosen brand in its dark theme', (
    tester,
  ) async {
    const blue = DashBrand(
      dark: DashAccent(fill: Color(0xFF9FC5FF), ink: Color(0xFF9FC5FF)),
      light: DashAccent(fill: Color(0xFF4A7FD0), ink: Color(0xFF2A5AA0)),
      onAccent: Color(0xFF0A1830),
    );
    // The idle box shows the time, which in the 64 px test font fits on one
    // line only up to 9:59; from 10:00 it wrapped and overflowed the box.
    await withClock(
      Clock.fixed(DateTime(2026, 1, 1, 9, 41)),
      () => pumpPhone(
        tester,
        Theme(
          data: buildDashThemeData(Brightness.light, brand: blue),
          child: const ControllerSaver(printerId: 1),
        ),
        overrides: [
          noServerProfileOverride,
          fixedDashboardOverride(
            const DashboardState(
              printers: [
                PrinterWithStatus(
                  printer: Printer(id: 1, name: 'X1C', model: 'X1C'),
                  status: PrinterStatus(id: 1, connected: true, state: 'IDLE'),
                ),
              ],
            ),
          ),
          inertStatusesOverride,
        ],
      ),
    );

    final inside = tester.element(
      find
          .descendant(
            of: find.byType(ControllerSaver),
            matching: find.byType(Material),
          )
          .first,
    );
    final t = DashTokens.of(inside);
    expect(t.brightness, Brightness.dark);
    expect(t.brand, blue);
  });
}
