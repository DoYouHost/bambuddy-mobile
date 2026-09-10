import 'package:bambuddy_mobile/core/models/archive_stats.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a per-printer breakdown gets its labels. Two sources answer the same
/// question and disagree on purpose: the live printer list knows the current
/// name of a printer that still exists, and the server's print log (#2873,
/// server 1.2.5.4+) knows the last name of one that was deleted — which the
/// live list cannot name at all, leaving its history reading as a bare id.
class _FakeStatsNotifier extends StatsNotifier {
  _FakeStatsNotifier(this._stats);

  final ArchiveStats _stats;

  @override
  Future<ArchiveStats> build() async => _stats;
}

void main() {
  Future<Map<int, String>> labels({
    required Map<String, String> recorded,
    required Map<int, String> live,
  }) async {
    final container = ProviderContainer(
      overrides: [
        statsProvider.overrideWith(
          () => _FakeStatsNotifier(ArchiveStats(printerNames: recorded)),
        ),
        livePrinterNamesProvider.overrideWith((ref) async => live),
      ],
    );
    addTearDown(container.dispose);
    // Both sources are async and the merge reads them synchronously, so they
    // have to have landed before it is read at all.
    container.listen(printerLabelsProvider, (_, _) {});
    await container.read(statsProvider.future);
    await container.read(livePrinterNamesProvider.future);
    return container.read(printerLabelsProvider);
  }

  test('a deleted printer keeps the name its prints were made under', () async {
    expect(await labels(recorded: const {'71': 'Ultron'}, live: const {}), {
      71: 'Ultron',
    });
  });

  test(
    'a live printer is named from the live list, so a rename shows at once',
    () async {
      expect(
        await labels(
          recorded: const {'1': 'Old name', '71': 'Ultron'},
          live: const {1: 'New name'},
        ),
        {1: 'New name', 71: 'Ultron'},
      );
    },
  );

  test('an older server sends no names, which changes nothing', () async {
    expect(await labels(recorded: const {}, live: const {1: 'X1C'}), {
      1: 'X1C',
    });
  });

  test('a key that is not an id is dropped rather than guessed', () async {
    expect(
      await labels(recorded: const {'not-an-id': 'Ghost'}, live: const {}),
      isEmpty,
    );
  });

  test('a nameless live printer does not blank out the recorded name', () async {
    // `PrinterUpdate.name` has no minimum length and the PATCH route assigns it
    // unchecked, so a printer really can end up with an empty name. Letting it
    // win would draw a bar with nothing written on it — the `#id` fallback only
    // fires when the label is missing, and an empty string is not missing.
    expect(
      await labels(recorded: const {'71': 'Ultron'}, live: const {71: ''}),
      {71: 'Ultron'},
    );
  });

  test(
    'a printer nameless on both sides is left to the row fallback',
    () async {
      expect(
        await labels(recorded: const {'71': '   '}, live: const {71: ''}),
        isEmpty,
      );
    },
  );

  test('a caller that may not read /printers still gets names', () async {
    // An API key reaches the archives but not the printer list, so the live
    // half never resolves. The recorded names are the whole label then —
    // without them every bar on the screen reads as a bare `#id`.
    final container = ProviderContainer(
      overrides: [
        statsProvider.overrideWith(
          () => _FakeStatsNotifier(
            ArchiveStats(printerNames: const {'1': 'Ultron', '7': 'Vision'}),
          ),
        ),
        livePrinterNamesProvider.overrideWith(
          (ref) async => throw StateError('403'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(printerLabelsProvider, (_, _) {});
    await container.read(statsProvider.future);
    await expectLater(
      container.read(livePrinterNamesProvider.future),
      throwsStateError,
    );

    expect(container.read(printerLabelsProvider), {1: 'Ultron', 7: 'Vision'});
  });
}
