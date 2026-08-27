import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/screens/wear_printer_control_screen.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The watch's own end of the HMS work: it reads the faults out of the fleet
/// poll it already runs, and its buttons go through the same transport as
/// pause/stop — the relay when the phone is near, REST when it is not.
class _FakeTransport implements WearTransport {
  _FakeTransport(this._fleet);

  final WearFleet _fleet;
  final List<String> calls = [];

  @override
  Future<WearFleet> getFleet() async => _fleet;

  @override
  Future<void> clearHmsErrors(int printerId) async =>
      calls.add('clear:$printerId');

  @override
  Future<void> executeHmsAction(
    int printerId, {
    required String printError,
    required String action,
    String? jobId,
  }) async =>
      calls.add('action:$printerId:$printError:$action:${jobId ?? ''}');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

class _NoProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

/// Filament runout, as the server reports it on the `print_error` channel.
const _runout = HmsError(
  code: '0x8004',
  attr: 0x03008004,
  module: 3,
  severity: 3,
  fullCode: '03008004',
  jobId: '746795586',
  actions: ['RESUME_PRINTING', 'STOP_PRINTING'],
);

/// A component-diagnostics fault from the `hms[]` channel — named by neither
/// bambuddy nor the app, on the phone or here.
const _diagnostics =
    HmsError(code: '0x20070', attr: 83887616, module: 5, severity: 2);

WearFleet _fleetWith(List<HmsError> errors, {bool connected = true}) =>
    WearFleet(
      printers: [
        PrinterWithStatus(
          printer: const Printer(id: 7, name: 'X1C'),
          status: PrinterStatus(
            id: 7,
            connected: connected,
            state: 'PAUSE',
            progress: 40,
            hmsErrors: errors,
          ),
        ),
      ],
    );

Future<_FakeTransport> _pumpControl(
  WidgetTester tester,
  List<HmsError> errors, {
  bool connected = true,
}) async {
  final transport =
      _FakeTransport(_fleetWith(errors, connected: connected));
  await pumpWear(
    tester,
    const WearPrinterControlScreen(printerId: 7),
    overrides: [
      serverProfileProvider.overrideWith(_NoProfileNotifier.new),
      wearTransportProvider.overrideWith(
        (ref) => HybridWearTransport(relay: transport),
      ),
      requirePlateClearProvider.overrideWith((ref) async => false),
    ],
  );
  return transport;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await HmsCatalog.instance.load(const Locale('pl'));
  });

  testWidgets('a fault is named, and offers the buttons its firmware lists',
      (tester) async {
    await _pumpControl(tester, const [_runout]);

    expect(find.textContaining('Skończył się filament'), findsOneWidget);
    expect(find.text('0300-8004'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Wznów'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Zatrzymaj'), findsWidgets);
    // Last row of a fault card that already fills the face: a scroll away.
    await revealOnWatch(tester, find.text('Odrzuć wszystkie'));
    expect(find.text('Odrzuć wszystkie'), findsOneWidget);
  });

  testWidgets('an unreachable printer offers no faults to act on',
      (tester) async {
    // `hms_errors` is deliberately carried forward across a disconnect so the
    // phone's alert memory can hold still. On screen those are last-known
    // values: shown here they would read as live faults under an OFFLINE chip,
    // each with a button the server answers "Printer not connected".
    await _pumpControl(tester, const [_runout], connected: false);

    expect(find.textContaining('Skończył się filament'), findsNothing);
    expect(find.text('0300-8004'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Wznów'), findsNothing);
    expect(find.text('Odrzuć wszystkie'), findsNothing);
  });

  testWidgets('an unnameable fault is not shown on the watch either',
      (tester) async {
    await _pumpControl(tester, const [_diagnostics]);

    expect(find.textContaining('0500-0600'), findsNothing);
    expect(find.text('Odrzuć wszystkie'), findsNothing);
  });

  testWidgets('an action carries the fault through to the transport',
      (tester) async {
    final transport = await _pumpControl(tester, const [_runout]);

    await tapOnWatch(tester, find.widgetWithText(FilledButton, 'Wznów'));
    await tester.pumpAndSettle();

    expect(transport.calls, ['action:7:03008004:RESUME_PRINTING:746795586']);
  });

  testWidgets('stopping the print asks first, on the watch too', (tester) async {
    final transport = await _pumpControl(tester, const [_runout]);

    // The fault's own stop button, not the lifecycle bar's below it.
    await tapOnWatch(tester, find.widgetWithText(FilledButton, 'Zatrzymaj').first);
    await tester.pumpAndSettle();
    expect(transport.calls, isEmpty, reason: 'nothing before the confirmation');

    await tapOnWatch(tester, find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(transport.calls, ['action:7:03008004:STOP_PRINTING:746795586']);
  });

  testWidgets('dismiss-all clears the printer', (tester) async {
    final transport = await _pumpControl(tester, const [_runout]);

    await tapOnWatch(tester, find.text('Odrzuć wszystkie'));
    await tester.pumpAndSettle();

    expect(transport.calls, ['clear:7']);
  });
}
