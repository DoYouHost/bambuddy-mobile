import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/alarm/alarm_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

void main() {
  late List<MethodCall> native;

  // The alarm's own copy, as `PrintAlarm.ring` hands it over: already localized,
  // not this app's arb strings.
  const finished = (
    title: 'Print finished',
    body: 'Benchy is done',
    printer: 'X1C',
  );
  final oneAlarm = (alarms: [finished], stop: pl.alarmStop);

  Future<void> pump(
    WidgetTester tester, {
    double textScale = 1,
    AlarmContent? content,
  }) async {
    native = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      alarmScreenChannel,
      (call) async {
        native.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        alarmScreenChannel,
        null,
      ),
    );
    usePhoneWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDashThemeData(Brightness.dark, brand: bambuddyBrand),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: AlarmScreen(initial: content ?? oneAlarm),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows what rang and a Stop', (tester) async {
    await pump(tester);
    expect(find.text(finished.printer), findsOneWidget);
    expect(find.text(finished.title), findsOneWidget);
    expect(find.text(finished.body), findsOneWidget);
    expect(find.widgetWithText(FilledButton, pl.alarmStop), findsOneWidget);
  });

  testWidgets('Stop asks the activity to stop every alarm', (tester) async {
    await pump(tester);
    await tester.tap(find.text(pl.alarmStop));
    await tester.pump();
    expect(native.map((c) => c.method), ['stop']);
  });

  testWidgets('the test alarm has no printer line', (tester) async {
    await pump(
      tester,
      content: (
        alarms: [
          (title: 'Test alarm', body: 'This is how it sounds', printer: ''),
        ],
        stop: 'Stop',
      ),
    );
    expect(find.text('Test alarm'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets('a later alarm updates what the screen shows', (tester) async {
    await pump(tester);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      alarmScreenChannel.name,
      alarmScreenChannel.codec.encodeMethodCall(
        const MethodCall('show', {
          'stop': 'Stop',
          'alarms': [
            {'title': 'Drying finished', 'body': 'AMS 1', 'printer': 'P1S'},
            {
              'title': 'Print finished',
              'body': 'Benchy is done',
              'printer': 'X1C',
            },
          ],
        }),
      ),
      (_) {},
    );
    await tester.pump();
    // Every alarm still ringing, each with its printer.
    expect(find.text('Drying finished'), findsOneWidget);
    expect(find.text('P1S'), findsOneWidget);
    expect(find.text(finished.title), findsOneWidget);
    expect(find.text('X1C'), findsOneWidget);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('lays out without overflow at text scale $scale', (
      tester,
    ) async {
      // Three printers at once is the tallest the screen gets.
      await pump(
        tester,
        textScale: scale,
        content: (
          alarms: [
            for (final name in ['X1C', 'P1S', 'H2D'])
              (
                title: 'Print stopped by a fault',
                body: 'Filament ran out. Please load new filament.',
                printer: name,
              ),
          ],
          stop: pl.alarmStop,
        ),
      );
      expect(tester.takeException(), isNull);
      // Stop has to stay reachable: scrolled into view at the largest font.
      await tester.ensureVisible(find.text(pl.alarmStop));
      expect(find.text(pl.alarmStop).hitTestable(), findsOneWidget);
    });
  }
}
