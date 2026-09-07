import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ams_slot_config_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each source answers independently, so every one can be told to fail on its
/// own — which is the whole point of the provider under test.
class _FakeRepo implements AmsSlotConfigRepository {
  Object? cloudError;
  Object? localError;
  Object? builtinError;
  Object? modelsError;

  @override
  Future<List<AmsFilamentPreset>> cloudFilaments() async {
    if (cloudError != null) throw cloudError!;
    return const [
      AmsFilamentPreset(
        source: AmsPresetSource.cloud,
        id: 'GFSL05',
        name: 'Bambu PLA Basic',
      ),
    ];
  }

  @override
  Future<List<AmsFilamentPreset>> localFilaments() async {
    if (localError != null) throw localError!;
    return const [
      AmsFilamentPreset(
        source: AmsPresetSource.local,
        id: '7',
        name: 'eSUN PETG',
      ),
    ];
  }

  @override
  Future<List<AmsFilamentPreset>> builtinFilaments() async {
    if (builtinError != null) throw builtinError!;
    return const [
      AmsFilamentPreset(
        source: AmsPresetSource.builtin,
        id: 'GFL99',
        name: 'Generic PLA',
      ),
    ];
  }

  @override
  Future<Map<String, String>> printerModels() async {
    if (modelsError != null) throw modelsError!;
    return const {'Bambu Lab X1 Carbon': 'X1C'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not part of this test',
  );
}

ProviderContainer _container(_FakeRepo repo) {
  final c = ProviderContainer(
    overrides: [amsSlotConfigRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('collects all four sources', () async {
    final sources = await _container(
      _FakeRepo(),
    ).read(slotPresetSourcesProvider.future);

    expect(sources.cloud, hasLength(1));
    expect(sources.local, hasLength(1));
    expect(sources.builtin, hasLength(1));
    expect(sources.printerModels, {'Bambu Lab X1 Carbon': 'X1C'});
    expect(sources.cloudNeedsLogin, isFalse);
    expect(sources.isEmpty, isFalse);
  });

  test(
    'a missing Bambu Cloud login costs one tier and asks for a login',
    () async {
      // The most common state by far: the app works fine without a cloud
      // account, and the picker still has the imported and built-in tiers.
      final repo = _FakeRepo()
        ..cloudError = const AuthException(AppErrorCode.unauthorized);

      final sources = await _container(
        repo,
      ).read(slotPresetSourcesProvider.future);

      expect(sources.cloud, isEmpty);
      expect(sources.cloudNeedsLogin, isTrue);
      expect(sources.local, hasLength(1));
      expect(sources.builtin, hasLength(1));
    },
  );

  test(
    'a cloud failure that is not a login problem does not ask for a login',
    () async {
      // Nagging a logged-in user to log in is worse than saying nothing.
      final repo = _FakeRepo()
        ..cloudError = const ApiException(AppErrorCode.serverUnreachable);

      final sources = await _container(
        repo,
      ).read(slotPresetSourcesProvider.future);

      expect(sources.cloud, isEmpty);
      expect(sources.cloudNeedsLogin, isFalse);
    },
  );

  test('a key without settings:read still gets the other tiers', () async {
    final repo = _FakeRepo()
      ..localError = const AuthException(AppErrorCode.forbidden);

    final sources = await _container(
      repo,
    ).read(slotPresetSourcesProvider.future);

    expect(sources.local, isEmpty);
    expect(sources.cloud, hasLength(1));
    expect(sources.builtin, hasLength(1));
  });

  test('losing the registry leaves the presets, unfiltered', () async {
    // Without it every preset classifies as "names no printer", which the
    // catalogue keeps — fewer presets hidden, never a wrong one.
    final repo = _FakeRepo()
      ..modelsError = const ApiException(AppErrorCode.badResponse);

    final sources = await _container(
      repo,
    ).read(slotPresetSourcesProvider.future);

    expect(sources.printerModels, isEmpty);
    expect(sources.isEmpty, isFalse);
  });

  test('every source failing is reported as empty, not as an error', () async {
    // The sheet still opens; it just has nothing to offer, and says so.
    final repo = _FakeRepo()
      ..cloudError = const ApiException(AppErrorCode.serverUnreachable)
      ..localError = const ApiException(AppErrorCode.serverUnreachable)
      ..builtinError = const ApiException(AppErrorCode.serverUnreachable)
      ..modelsError = const ApiException(AppErrorCode.serverUnreachable);

    final sources = await _container(
      repo,
    ).read(slotPresetSourcesProvider.future);

    expect(sources.isEmpty, isTrue);
  });
}
