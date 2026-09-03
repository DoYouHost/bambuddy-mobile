import 'package:bambuddy_mobile/core/models/archive_stats.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePrintersRepo extends PrintersRepository {
  _FakePrintersRepo(this._printers) : super(Dio());

  final List<Printer> _printers;

  @override
  Future<List<Printer>> fetchPrinters() async => _printers;
}

class _FakeStatsNotifier extends StatsNotifier {
  _FakeStatsNotifier(this._stats);

  final ArchiveStats _stats;

  @override
  Future<ArchiveStats> build() async => _stats;
}

void main() {
  Future<Map<int, String>> resolve({
    required List<Printer> printers,
    required Map<String, String> recorded,
  }) async {
    final container = ProviderContainer(overrides: [
      printersRepositoryProvider.overrideWithValue(_FakePrintersRepo(printers)),
      statsProvider.overrideWith(
        () => _FakeStatsNotifier(ArchiveStats(printerNames: recorded)),
      ),
    ]);
    addTearDown(container.dispose);
    // Auto-dispose: something has to hold them the way the Stats screen does.
    container.listen(statsProvider, (_, _) {});
    container.listen(printerNamesProvider, (_, _) {});
    // The stats have to land first, or the first computation sees no names at
    // all — which is the older-server case covered separately below.
    await container.read(statsProvider.future);
    return container.read(printerNamesProvider.future);
  }

  test('a live printer is named from the live record, so a rename shows up',
      () async {
    final names = await resolve(
      printers: const [Printer(id: 1, name: 'Ultron mk2')],
      recorded: const {'1': 'Ultron'},
    );

    expect(names[1], 'Ultron mk2');
  });

  test('an id the live list does not cover is named from the recorded names',
      () async {
    final names = await resolve(
      printers: const [Printer(id: 1, name: 'Ultron')],
      recorded: const {'1': 'Ultron', '7': 'Vision'},
    );

    expect(names[1], 'Ultron');
    expect(names[7], 'Vision');
  });

  test('a caller that cannot read /printers still gets names', () async {
    final names = await resolve(
      printers: const [],
      recorded: const {'1': 'Ultron', '7': 'Vision'},
    );

    expect(names, {1: 'Ultron', 7: 'Vision'});
  });

  test('a non-numeric key is ignored rather than crashing the map', () async {
    final names = await resolve(
      printers: const [],
      recorded: const {'not-an-id': 'Nobody', '3': 'Jarvis'},
    );

    expect(names, {3: 'Jarvis'});
  });

  test('without printer_names the map is the live printers, as before',
      () async {
    final names = await resolve(
      printers: const [Printer(id: 2, name: 'Wanda')],
      recorded: const {},
    );

    expect(names, {2: 'Wanda'});
  });
}
