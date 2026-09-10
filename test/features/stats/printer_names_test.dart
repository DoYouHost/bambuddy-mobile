import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live half of a per-printer label. What happens when it cannot name an
/// id — because the printer was deleted, or because this credential may not
/// read `/printers` at all — is `printerLabelsProvider`'s question, and is
/// covered in `printer_labels_provider_test.dart`.
class _FakePrintersRepo extends PrintersRepository {
  _FakePrintersRepo(this._printers) : super(Dio());

  final List<Printer> _printers;

  @override
  Future<List<Printer>> fetchPrinters() async => _printers;
}

class _RefusingPrintersRepo extends PrintersRepository {
  _RefusingPrintersRepo() : super(Dio());

  @override
  Future<List<Printer>> fetchPrinters() async => throw StateError('403');
}

void main() {
  ProviderContainer containerWith(PrintersRepository repo) {
    final container = ProviderContainer(
      overrides: [printersRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // Auto-dispose: something has to hold it the way the Stats screen does.
    container.listen(livePrinterNamesProvider, (_, _) {});
    return container;
  }

  test('every live printer is named by its current name', () async {
    final container = containerWith(
      _FakePrintersRepo(const [
        Printer(id: 1, name: 'Ultron mk2'),
        Printer(id: 7, name: 'Vision'),
      ]),
    );

    expect(await container.read(livePrinterNamesProvider.future), {
      1: 'Ultron mk2',
      7: 'Vision',
    });
  });

  test('no printers at all is an empty map, not an error', () async {
    final container = containerWith(_FakePrintersRepo(const []));

    expect(await container.read(livePrinterNamesProvider.future), isEmpty);
  });

  test('a refused listing surfaces as the error state', () async {
    final container = containerWith(_RefusingPrintersRepo());

    await expectLater(
      container.read(livePrinterNamesProvider.future),
      throwsStateError,
    );
    expect(container.read(livePrinterNamesProvider).valueOrNull, isNull);
  });
}
