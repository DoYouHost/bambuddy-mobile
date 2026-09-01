import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/screens/wear_printer_control_screen.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// An empty fleet: what the control screen gets when the printer it was opened
/// for has gone from the poll.
class _EmptyTransport implements WearTransport {
  @override
  Future<WearFleet> getFleet() async =>
      const WearFleet(printers: [], queuePending: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

class _NoProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

void main() {
  for (final face in [wearFaceSmall, wearFaceLarge]) {
    testWidgets(
        'a printer that has gone says so on the glass of a '
        '${face.width.toInt()} px face', (tester) async {
      await pumpWear(
        tester,
        const WearPrinterControlScreen(printerId: 7),
        face: face,
        overrides: [
          serverProfileProvider.overrideWith(_NoProfileNotifier.new),
          wearTransportProvider.overrideWith(
            (ref) => HybridWearTransport(relay: _EmptyTransport()),
          ),
          requirePlateClearProvider.overrideWith((ref) async => false),
        ],
      );

      // The screen's one state that never reaches `WearScrollView`, and so the
      // one that has to ask for the round-safe rectangle by hand.
      expectOnGlass(tester, find.text('Drukarka niedostępna'));
    });
  }
}
