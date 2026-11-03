import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/dashboard/dashboard_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/settings/app_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets, measured on the pixels a screen
/// paints: the token audit cannot see a colour typed into a widget or text
/// over a picture. The app-wide coverage plan is docs/plans/a11y-guideline-tests.md;
/// the harness is a11y_harness.dart, the other surfaces live in `<feature>_a11y_test.dart`.
void main() {
  a11ySurface(
    'app settings',
    demo: false,
    home: () => const AppSettingsScreen(),
  );

  // Each section of the screen, as the segments switch it.
  for (final (section, icon) in [
    ('watch', Icons.watch_outlined),
    ('labelPrinter', Icons.label_outline),
  ]) {
    a11ySurface(
      'app settings, $section',
      demo: false,
      home: () => const AppSettingsScreen(),
      arrange: (tester) async {
        await tester.tap(
          find.descendant(
            of: byLogId('app_settings.section'),
            matching: find.byIcon(icon),
          ),
        );
        await tester.pumpAndSettle();
      },
    );
  }

  a11ySurface(
    'dashboard',
    demo: false,
    overrides: _dashboardOverrides,
    home: () => const DashboardScreen(),
  );

  a11ySurface(
    'bottom sheet',
    demo: false,
    home: () => const _Launcher(),
    arrange: (tester) async {
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
    },
  );

  a11ySurface(
    'confirm dialog',
    demo: false,
    home: () => const _Launcher(),
    arrange: (tester) async {
      await tester.tap(find.text('dialog'));
      await tester.pumpAndSettle();
    },
  );
}

final _dashboardOverrides = [
  fixedDashboardOverride(
    const DashboardState(
      printers: [
        PrinterWithStatus(
          printer: Printer(id: 1, name: 'X1C-01', model: 'X1C'),
          status: PrinterStatus(
            id: 1,
            connected: true,
            state: 'RUNNING',
            progress: 64,
            remainingTime: 72,
          ),
        ),
      ],
    ),
  ),
  fakeServerProfileOverride(),
  inertStatusesOverride,
  inertSmartPlugsOverride,
  inertFirmwareOverride,
  inertAnnouncementsOverride,
  inertExternalLinksOverride,
  inertTotalPrintHoursOverride,
  ...a11yPlatformOverrides,
  wsConnectionStateProvider.overrideWith(
    (ref) => Stream.value(WsConnectionState.connected),
  ),
];

/// Opens the shared sheet and confirmation dialog, filled the way the app
/// fills them, so the overlay ground is measured under every brand.
class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () => dashSheet<void>(
            context,
            builder: (_) => SettingsCard(
              rows: [
                SettingsSwitchRow(
                  tag: 'a11y.row',
                  title: 'Keep the bed warm',
                  subtitle: 'Between two chamber-heated prints',
                  value: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          child: const Text('sheet'),
        ),
        TextButton(
          onPressed: () => confirmDialog(
            context,
            id: 'a11y.confirm',
            title: 'Delete the spool?',
            message: 'Its history stays in the archive.',
            confirmLabel: 'Delete',
            destructive: true,
          ),
          child: const Text('dialog'),
        ),
      ],
    ),
  );
}
