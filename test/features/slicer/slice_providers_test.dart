import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the preset-values provider actually asked for, so the family's
/// caching and the ref it puts on the wire are both observable.
class _CountingRepository extends SlicerRepository {
  _CountingRepository() : super(Dio());

  final asked = <(String, String)>[];

  @override
  Future<PresetValues?> presetValues(SlicerPreset preset) async {
    asked.add((preset.source, preset.id));
    return const PresetValues(resolved: true, reason: 'ok');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container({List<Override> overrides = const []}) {
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    return c;
  }

  group('processSchemaProvider', () {
    test('loads the vendored metadata', () async {
      final c = container();
      final catalog = await c.read(processSchemaProvider.future);
      expect(catalog, isNotNull);
      expect(catalog!.schema, isNotEmpty);
      expect(catalog.tree, isNotEmpty);
    });
  });

  group('processSettingsAvailableProvider', () {
    Future<bool> available({
      required bool serverAccepts,
      bool assetsLoad = true,
    }) {
      final c = container(
        overrides: [
          processOverridesProvider.overrideWith((ref) async => serverAccepts),
          if (!assetsLoad)
            processSchemaProvider.overrideWith((ref) async => null),
        ],
      );
      return c.read(processSettingsAvailableProvider.future);
    }

    test('needs the server to accept process_overrides', () async {
      expect(await available(serverAccepts: false), isFalse);
      expect(await available(serverAccepts: true), isTrue);
    });

    test('needs our own assets to have loaded', () async {
      // A broken asset is our build's problem, not the server's, and the two
      // fail independently — hence one gate rather than two checks in the sheet.
      expect(await available(serverAccepts: true, assetsLoad: false), isFalse);
    });

    test('an older server is not asked about the assets at all', () async {
      // Short-circuit: below 1.2.6 there is nothing to show regardless, and
      // decoding 156 KB to discover that would be wasted on every slice.
      final c = container(
        overrides: [
          processOverridesProvider.overrideWith((ref) async => false),
          processSchemaProvider.overrideWith(
            (ref) async => throw StateError('should not be read'),
          ),
        ],
      );
      expect(await c.read(processSettingsAvailableProvider.future), isFalse);
    });
  });

  group('presetValuesProvider', () {
    test('puts the preset source and id on the wire', () async {
      final repo = _CountingRepository();
      final c = container(
        overrides: [slicerRepositoryProvider.overrideWithValue(repo)],
      );

      await c.read(presetValuesProvider(('local', '12')).future);
      expect(repo.asked, [('local', '12')]);
    });

    test('the same preset is one read, a different one is another', () async {
      // The reason the family key is a record: SlicerPreset compares by
      // identity, so keying on it would refetch the same preset on every
      // rebuild of the sheet.
      final repo = _CountingRepository();
      final c = container(
        overrides: [slicerRepositoryProvider.overrideWithValue(repo)],
      );

      // Listening keeps the autoDispose family alive between reads, as a widget
      // watching it would.
      const first = ('local', '12');
      const same = ('local', '12');
      const other = ('cloud', '99');
      for (final key in [first, same, other]) {
        c.listen(presetValuesProvider(key), (_, _) {});
      }
      await c.read(presetValuesProvider(first).future);
      await c.read(presetValuesProvider(same).future);
      await c.read(presetValuesProvider(other).future);

      expect(repo.asked, [('local', '12'), ('cloud', '99')]);
    });
  });
}
