import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Live statuses the test can change, as the socket would.
class _Statuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => const {};

  void put(PrinterStatus status) => state = {...state, status.id: status};
}

void main() {
  late _Statuses statuses;

  ProviderContainer container({List<PrinterWithStatus>? roster}) {
    statuses = _Statuses();
    final c = ProviderContainer(
      retry: neverRetry,
      overrides: [
        fixedDashboardOverride(DashboardState(printers: roster)),
        printerStatusesProvider.overrideWith(() => statuses),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  final roster = [
    PrinterWithStatus(
      printer: const Printer(id: 1, name: 'P1', model: 'P1S'),
      status: const PrinterStatus(id: 1, connected: true, state: 'IDLE'),
    ),
  ];

  group('controllerModelProvider', () {
    test('yields the model of its printer', () {
      final c = container(roster: roster);

      expect(c.read(controllerModelProvider(1)), 'P1S');
      expect(c.read(controllerPrinterInfoProvider(1))?.name, 'P1');
    });

    test('is null while the roster has not arrived', () {
      final c = container();

      expect(c.read(controllerModelProvider(1)), isNull);
      expect(c.read(controllerPrinterInfoProvider(1)), isNull);
    });

    test('is null for a printer the server does not have', () {
      final c = container(roster: roster);

      expect(c.read(controllerModelProvider(7)), isNull);
      expect(c.read(controllerPrinterInfoProvider(7)), isNull);
    });

    test('does not notify when only the live status changes', () {
      final c = container(roster: roster);
      var models = 0;
      var infos = 0;
      c.listen(controllerModelProvider(1), (_, _) => models++);
      c.listen(controllerPrinterInfoProvider(1), (_, _) => infos++);

      statuses.put(
        const PrinterStatus(id: 1, connected: true, state: 'RUNNING'),
      );

      expect(
        c.read(controllerPrinterProvider(1)).item!.status!.state,
        'RUNNING',
      );
      expect(models, 0);
      expect(infos, 0);
    });
  });
}
