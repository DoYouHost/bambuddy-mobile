import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Printers extends PrintersRepository {
  _Printers() : super(Dio());

  @override
  Future<List<PrinterWithStatus>> fetchAll() async {
    // A real server answers later than the turn in which the provider is
    // disposed for having no listener.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const [
      PrinterWithStatus(
        printer: Printer(id: 1, name: 'X1C', model: 'X1C', nozzleCount: 1),
      ),
    ];
  }
}

class _Plugs extends SmartPlugsRepository {
  _Plugs() : super(Dio());

  @override
  Future<List<SmartPlug>> fetchPlugs() async => const [];
}

void main() {
  group('availablePrintersProvider', () {
    test('answers when read once with nothing listening', () async {
      // The queue's start flow reads `.future` and does not watch it, so
      // Riverpod disposes the provider at its first await; a `ref.read` after
      // that await threw `UnmountedRefException` and the picker never opened.
      final container = ProviderContainer(
        overrides: [
          printersRepositoryProvider.overrideWithValue(_Printers()),
          smartPlugsRepositoryProvider.overrideWithValue(_Plugs()),
        ],
      );
      addTearDown(container.dispose);

      final candidates = await container.read(availablePrintersProvider.future);

      expect(candidates.map((c) => c.printer.id), [1]);
      expect(candidates.single.hasPlug, isFalse);
    });
  });
}
