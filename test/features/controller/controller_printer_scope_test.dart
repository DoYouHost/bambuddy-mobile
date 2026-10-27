import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bambuddy_mobile/providers.dart';

import '../../helpers.dart';

/// Live statuses the test can change, as the socket would.
class _Statuses extends PrinterStatusesNotifier {
  _Statuses(this._initial);

  final Map<int, PrinterStatus> _initial;

  @override
  Map<int, PrinterStatus> build() => _initial;

  void put(PrinterStatus status) => state = {...state, status.id: status};
}

HmsError _fault(String message) => HmsError(code: '0x10001', message: message);

PrinterWithStatus _printer(int id, {List<HmsError> faults = const []}) =>
    PrinterWithStatus(
      printer: Printer(id: id, name: 'P$id'),
      status: PrinterStatus(id: id, connected: true, hmsErrors: faults),
    );

void main() {
  late _Statuses statuses;

  ProviderContainer container({
    List<PrinterWithStatus>? roster,
    Map<int, PrinterStatus> live = const {},
  }) {
    statuses = _Statuses(live);
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

  group('controllerPrinterProvider', () {
    test('finds its printer in the roster', () {
      final c = container(roster: [_printer(1), _printer(2)]);

      final printer = c.read(controllerPrinterProvider(2));

      expect(printer.rosterKnown, isTrue);
      expect(printer.item!.printer.name, 'P2');
    });

    test('says so while the roster has not arrived', () {
      final c = container();

      final printer = c.read(controllerPrinterProvider(1));

      expect(printer.rosterKnown, isFalse);
      expect(printer.item, isNull);
    });

    test('a printer the server does not have is known to be missing', () {
      final c = container(roster: [_printer(1)]);

      final printer = c.read(controllerPrinterProvider(7));

      expect(printer.rosterKnown, isTrue);
      expect(printer.item, isNull);
    });

    test('puts the live status over the roster\'s', () {
      final c = container(
        roster: [_printer(1)],
        live: {
          1: const PrinterStatus(id: 1, connected: true, state: 'RUNNING'),
        },
      );

      expect(
        c.read(controllerPrinterProvider(1)).item!.status!.state,
        'RUNNING',
      );
    });

    test('a status frame of another printer does not reach this one', () {
      final c = container(roster: [_printer(1), _printer(2)]);
      var rebuilt = 0;
      c.listen(controllerPrinterProvider(1), (_, _) => rebuilt++);

      statuses.put(
        const PrinterStatus(id: 2, connected: true, state: 'RUNNING'),
      );
      c.read(controllerPrinterProvider(1));

      expect(rebuilt, 0);
    });

    test('its own status frame does', () {
      final c = container(roster: [_printer(1), _printer(2)]);
      var rebuilt = 0;
      c.listen(controllerPrinterProvider(1), (_, _) => rebuilt++);

      statuses.put(
        const PrinterStatus(id: 1, connected: true, state: 'RUNNING'),
      );
      c.read(controllerPrinterProvider(1));

      expect(rebuilt, 1);
    });
  });

  group('controllerErrorsProvider', () {
    test('lists its printer\'s errors and nobody else\'s', () {
      final c = container(
        roster: [
          _printer(1, faults: [_fault('mine')]),
          _printer(2, faults: [_fault('theirs')]),
        ],
      );

      expect(
        [for (final e in c.read(controllerErrorsProvider(1))) e.message],
        ['mine'],
      );
      expect(
        [for (final e in c.read(controllerErrorsProvider(2))) e.message],
        ['theirs'],
      );
    });

    test('a new error on another printer leaves this list alone', () {
      final c = container(roster: [_printer(1), _printer(2)]);
      expect(c.read(controllerErrorsProvider(1)), isEmpty);

      statuses.put(
        PrinterStatus(id: 2, connected: true, hmsErrors: [_fault('theirs')]),
      );

      expect(c.read(controllerErrorsProvider(1)), isEmpty);
      expect(c.read(controllerErrorsProvider(2)), hasLength(1));
    });

    test('a printer that is not connected has none', () {
      final c = container(
        roster: [
          PrinterWithStatus(
            printer: const Printer(id: 1, name: 'P1'),
            status: PrinterStatus(
              id: 1,
              connected: false,
              hmsErrors: [_fault('last known')],
            ),
          ),
        ],
      );

      expect(c.read(controllerErrorsProvider(1)), isEmpty);
    });

    test('an id that is not on the server has none', () {
      final c = container(
        roster: [
          _printer(1, faults: [_fault('mine')]),
        ],
      );

      expect(c.read(controllerErrorsProvider(9)), isEmpty);
    });
  });
}
