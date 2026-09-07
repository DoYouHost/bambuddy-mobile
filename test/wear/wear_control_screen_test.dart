import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/screens/wear_printer_control_screen.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

class _FakeTransport implements WearTransport {
  _FakeTransport(this.fleet);

  final WearFleet fleet;

  @override
  Future<WearFleet> getFleet() async => fleet;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

/// Records the acknowledgement, and can answer it the way a pre-#2864 server
/// did — through the relay, which forwards the server's words without their
/// status code.
class _PlateTransport implements WearTransport {
  _PlateTransport(this.fleet, {this.error});

  final WearFleet fleet;
  final Object? error;
  int acks = 0;

  @override
  Future<WearFleet> getFleet() async => fleet;

  @override
  Future<void> clearPlate(int printerId) async {
    acks++;
    if (error != null) throw error!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

/// An idle printer with a plate to free and nothing queued behind it: the one
/// state that puts a real button and a placeholder in the same column.
WearFleet _idle({String name = 'X2D-3DP'}) => WearFleet(
  printers: [
    PrinterWithStatus(
      printer: Printer(id: 7, name: name),
      status: const PrinterStatus(
        id: 7,
        connected: true,
        state: 'IDLE',
        awaitingPlateClear: true,
      ),
    ),
  ],
  queuePending: 0,
);

/// The same printer with its power cut — how every print ends with Auto Power
/// Off, and the state the acknowledgement has to survive.
WearFleet _offlineAwaiting() => WearFleet(
  printers: [
    PrinterWithStatus(
      printer: const Printer(id: 7, name: 'X2D-3DP'),
      status: const PrinterStatus(
        id: 7,
        connected: false,
        awaitingPlateClear: true,
      ),
    ),
  ],
  queuePending: 0,
);

Future<void> _pump(
  WidgetTester tester,
  WearFleet fleet, {
  Size face = wearFaceSmall,
  WearTransport? transport,
}) => pumpWear(
  tester,
  const WearPrinterControlScreen(printerId: 7),
  face: face,
  overrides: [
    noServerProfileOverride,
    wearTransportProvider.overrideWith(
      (ref) => HybridWearTransport(relay: transport ?? _FakeTransport(fleet)),
    ),
    requirePlateClearProvider.overrideWith((ref) async => true),
  ],
);

void main() {
  for (final face in [wearFaceSmall, wearFaceLarge]) {
    testWidgets('a printer that has gone says so on the glass of a '
        '${face.width.toInt()} px face', (tester) async {
      await _pump(tester, const WearFleet(printers: []), face: face);

      // The screen's one state that never reaches `WearScrollView`, and so the
      // one that has to ask for the round-safe rectangle by hand.
      expectOnGlass(tester, find.text('Drukarka niedostępna'));
    });
  }

  testWidgets('a placeholder is the size of the buttons it stands among', (
    tester,
  ) async {
    await _pump(tester, _idle());

    // "Nothing queued" is not a button you may press, and it is a disabled
    // FilledButton for exactly that reason: it used to be a hand-built pill
    // repeating the theme's height, radius and text style, which is three
    // numbers that drift the day the button theme moves.
    final placeholder = find.widgetWithText(FilledButton, 'Kolejka jest pusta');
    final button = find.widgetWithText(FilledButton, 'Zwolnij płytę');
    await revealOnWatch(tester, placeholder);

    expect(tester.widget<FilledButton>(placeholder).onPressed, isNull);
    expect(tester.getSize(placeholder).height, tester.getSize(button).height);
  });

  group('the plate-clear gate on an unreachable printer', () {
    final ack = find.widgetWithText(FilledButton, 'Zwolnij płytę');

    testWidgets('is offered on the watch too, and acknowledged from it', (
      tester,
    ) async {
      final transport = _PlateTransport(_offlineAwaiting());
      await _pump(tester, _offlineAwaiting(), transport: transport);
      await revealOnWatch(tester, ack);

      await tester.tap(ack);
      await tester.pumpAndSettle();

      expect(transport.acks, 1);
      expect(find.text('Płyta zwolniona'), findsOneWidget);
    });

    testWidgets('an old server\'s refusal is worded for the wrist, and the '
        'button stands down', (tester) async {
      // Relayed, so the status code is gone and the words are all there is —
      // which is why the classification is written against them.
      final transport = _PlateTransport(
        _offlineAwaiting(),
        error: WearRelayRemoteError(
          'badResponse',
          reason: 'Printer not connected',
        ),
      );
      await _pump(tester, _offlineAwaiting(), transport: transport);
      await revealOnWatch(tester, ack);

      await tester.tap(ack);
      await tester.pumpAndSettle();

      expect(find.text('Ten serwer wymaga drukarki online'), findsOneWidget);
      expect(ack, findsNothing);
    });
  });

  testWidgets('a printer name too long for the face is cut, not wrapped', (
    tester,
  ) async {
    await _pump(
      tester,
      _idle(name: 'Bambu Lab X1 Carbon w warsztacie na dole'),
    );

    final header = find.byType(WearHeader);
    final line = find.descendant(of: header, matching: find.byType(Text));
    expect(tester.widget<Text>(line).maxLines, 1);
    expectOnGlass(tester, header);
  });
}
