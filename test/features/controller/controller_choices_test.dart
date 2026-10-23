import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_move.dart';
import 'package:bambuddy_mobile/features/controller/controller_saver.dart';
import 'package:bambuddy_mobile/features/controller/controller_settings.dart';
import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The preset rows (step, length, saver time) are measured with the app's own
/// fonts: the test font is as wide as it is tall, so with it a label that fits
/// on a phone looks too wide, and the check would prove nothing.
void main() {
  setUpAll(loadAppFonts);

  const rows = [
    'controller.step_preset',
    'controller.length_preset',
    'controller.saver_after',
  ];

  for (final locale in AppLocalizations.supportedLocales) {
    for (final size in const [Size(832, 392), Size(1280, 800)]) {
      for (final screen in ['move', 'settings']) {
        testWidgets(
          'the preset buttons of $screen are one size, none cut short, '
          'in ${locale.languageCode} at ${size.width.round()}x${size.height.round()}',
          (tester) async {
            useLogicalWindow(tester, size);
            SharedPreferences.setMockInitialValues({});
            final sp = await SharedPreferences.getInstance();
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  sharedPreferencesProvider.overrideWithValue(sp),
                  noServerProfileOverride,
                  printerCommandsRepositoryProvider.overrideWithValue(
                    RecordingCommands(),
                  ),
                  fixedDashboardOverride(
                    const DashboardState(
                      printers: [
                        PrinterWithStatus(
                          printer: Printer(id: 1, name: 'X1C', model: 'X1C'),
                          status: PrinterStatus(
                            id: 1,
                            connected: true,
                            state: 'IDLE',
                          ),
                        ),
                      ],
                    ),
                  ),
                  inertStatusesOverride,
                ],
                child: MaterialApp(
                  theme: buildDashThemeData(
                    Brightness.dark,
                    brand: bambuddyBrand,
                  ),
                  locale: locale,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: ControllerSaverHost(
                    printerId: 1,
                    child: Scaffold(
                      body: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ScaleToFit(
                          child: screen == 'move'
                              ? const ControllerMove(printerId: 1)
                              : const ControllerSettings(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            final sizes = <double>{};
            var buttons = 0;
            for (final id in rows) {
              for (final button in byLogId(id).evaluate()) {
                buttons++;
                expect(
                  find.descendant(
                    of: find.byWidget(button.widget),
                    matching: find.byType(FittedBox),
                  ),
                  findsNothing,
                  reason: '$id scales its label',
                );
                final text = find.descendant(
                  of: find.byWidget(button.widget),
                  matching: find.byType(Text),
                );
                final paragraph =
                    text.evaluate().single.renderObject! as RenderParagraph;
                expect(
                  paragraph.didExceedMaxLines,
                  isFalse,
                  reason: '${paragraph.text.toPlainText()} is cut short',
                );
                sizes.add(paragraph.text.style!.fontSize!);
              }
            }
            expect(buttons, greaterThan(0));
            expect(sizes, hasLength(1), reason: 'one font size, not $sizes');
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
