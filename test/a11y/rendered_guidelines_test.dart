import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/dashboard_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/theme/app_brand.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/settings/app_settings_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// Rendered contrast and touch targets, measured on the pixels a screen
/// paints: the token audit cannot see a colour typed into a widget or text
/// over a picture. The app-wide coverage plan is docs/plans/a11y-guideline-tests.md.
void main() {
  // The default, the lightest preset fill, and the exact-grey path.
  const accents = [
    AccentSource.bambuddy,
    AccentSource.orange,
    AccentSource.graphite,
  ];

  Future<void> pumpThemed(
    WidgetTester tester,
    Widget home,
    AccentSource accent,
    Brightness brightness, {
    List<Override> overrides = const [],
  }) async {
    useLogicalWindow(tester, const Size(411, 2000));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides.isEmpty ? [noServerProfileOverride] : overrides,
        ],
        child: MaterialApp(
          theme: buildDashThemeData(
            brightness,
            brand: resolveBrand(accent, null),
          ),
          locale: const Locale('pl'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> meetsAll(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(const _ContrastBesideMisreads()));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  }

  for (final accent in accents) {
    for (final brightness in Brightness.values) {
      final name = '${accent.name}, ${brightness.name}';

      testWidgets('app settings: $name', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(tester, const AppSettingsScreen(), accent, brightness);
        await meetsAll(tester);
        handle.dispose();
      });

      // Each section of the screen, as the segments switch it.
      for (final section in ['watch', 'labelPrinter']) {
        testWidgets('app settings, $section: $name', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpThemed(
            tester,
            const AppSettingsScreen(),
            accent,
            brightness,
          );
          await tester.tap(
            find.descendant(
              of: byLogId('app_settings.section'),
              matching: find.byIcon(
                section == 'watch' ? Icons.watch_outlined : Icons.label_outline,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await meetsAll(tester);
          handle.dispose();
        });
      }

      testWidgets('dashboard: $name', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(
          tester,
          const DashboardScreen(),
          accent,
          brightness,
          overrides: _dashboardOverrides,
        );
        await meetsAll(tester);
        handle.dispose();
      });

      testWidgets('bottom sheet: $name', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(tester, const _Launcher(), accent, brightness);
        await tester.tap(find.text('sheet'));
        await tester.pumpAndSettle();
        await meetsAll(tester);
        handle.dispose();
      });

      testWidgets('confirm dialog: $name', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(tester, const _Launcher(), accent, brightness);
        await tester.tap(find.text('dialog'));
        await tester.pumpAndSettle();
        await meetsAll(tester);
        handle.dispose();
      });
    }
  }
}

/// [textContrastGuideline] minus two nodes it misreads. It takes the text
/// colour from the commonest light and dark pixels of the node's whole rect,
/// and both of these fool it:
///
/// * a section header: a short label ("WYGLĄD") in a full-width row leaves too
///   few text pixels — 1.11:1 for the short label, a pass for the same header
///   with a long one. Its ink is `accentInk`, which `dashContrastAudit` holds
///   at 4.5:1 on every ground;
/// * the dashboard's "next available" line: 12 px grey on a grey ground, where
///   the anti-aliased edges outnumber the glyph cores — 3.82:1 read, 8.39:1
///   between its brightest glyph pixel and the ground (graphite, dark).
class _ContrastBesideMisreads extends MinimumTextContrastGuideline {
  const _ContrastBesideMisreads();

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) ||
      data.flagsCollection.isHeader ||
      data.label.startsWith(pl.nextAvailableLabel);
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
  inertTotalPrintHoursOverride,
  inertBackgroundMonitorOverride,
  notificationServiceProvider.overrideWithValue(RecordingNotifications()),
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
