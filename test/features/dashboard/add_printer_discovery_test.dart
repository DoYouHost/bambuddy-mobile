import 'package:bambuddy_mobile/core/models/discovery.dart';
import 'package:bambuddy_mobile/core/printers/model_code.dart';
import 'package:bambuddy_mobile/data/discovery_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/add_printer_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('mapModelCode', () {
    test('turns the SSDP code into the short name the form stores', () {
      expect(mapModelCode('N10'), 'H3C');
      expect(mapModelCode('O1D'), 'H2D');
      expect(mapModelCode('BL-P001'), 'X1C');
    });

    test('a short name and an unknown code come back unchanged', () {
      expect(mapModelCode('H3C'), 'H3C');
      expect(mapModelCode('Z99'), 'Z99');
      expect(mapModelCode(''), '');
    });
  });

  testWidgets('a discovered H3C names its model and prefills it', (
    tester,
  ) async {
    usePhoneWindow(tester, dp: 2400);
    await pumpPhone(
      tester,
      const AddPrinterScreen(),
      overrides: [
        noServerProfileOverride,
        fixedDashboardOverride(),
        discoveryRepositoryProvider.overrideWithValue(
          _StubDiscovery(testDio()),
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(byLogId('add_printer.scan_network'));
    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();

    expect(find.text('192.168.1.41 · H3C'), findsOneWidget);
    expect(find.text('H3C'), findsNothing);

    await tester.tap(byLogId('add_printer.discovered'));
    await tester.pumpAndSettle();
    expect(find.text('H3C'), findsOneWidget);
  });
}

class _StubDiscovery extends DiscoveryRepository {
  _StubDiscovery(super.dio);

  @override
  Future<DiscoveryInfo> info() async =>
      const DiscoveryInfo(isDocker: false, subnets: ['192.168.1.0/24']);

  @override
  Future<void> startSsdp({double duration = 10.0}) async {}

  @override
  Future<void> stopSsdp() async {}

  @override
  Future<List<DiscoveredPrinter>> discoveredPrinters() async => const [
    DiscoveredPrinter(
      serial: '00M09A000000032',
      name: 'Workshop H3C',
      ipAddress: '192.168.1.41',
      model: 'N10',
    ),
  ];
}
