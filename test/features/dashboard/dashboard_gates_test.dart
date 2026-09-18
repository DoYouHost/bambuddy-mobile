import 'dart:async';

import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/data/ams_history_repository.dart';
import 'package:bambuddy_mobile/data/heater_history_repository.dart';
import 'package:bambuddy_mobile/data/scheduled_drying_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/scheduled_drying_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

/// The dashboard's capability gates against what the server answers. What
/// used to take a sheet invalidating the gate after a failed fetch, or a gate
/// awaiting a listing, is now the latch telling the gate itself.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late Completer<ServerVersion?> version;
  late ProviderContainer container;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    version = Completer();
    // Only the latch's `feature` needs a service; the gates read the version
    // through [serverVersionProvider].
    final service = ServerVersionService(dio);
    container = ProviderContainer(
      overrides: [
        fakeServerProfileOverride(),
        serverVersionProvider.overrideWith((ref) => version.future),
        heaterHistoryRepositoryProvider.overrideWithValue(
          HeaterHistoryRepository(dio, service),
        ),
        amsHistoryRepositoryProvider.overrideWithValue(
          AmsHistoryRepository(dio),
        ),
        scheduledDryingRepositoryProvider.overrideWithValue(
          ScheduledDryingRepository(dio, service),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  AsyncValue<bool> read(Provider<AsyncValue<bool>> gate) {
    container.listen(gate, (_, _) {});
    return container.read(gate);
  }

  Future<void> settleVersion(String raw) async {
    version.complete(ServerVersion.tryParse(raw));
    await pumpEventQueue();
  }

  test('a 404 inside the heater sheet takes the chart glyph away', () async {
    adapter.onGet(
      '/api/v1/printer-sensor-history/1',
      (s) => s.reply(404, {'detail': 'Not Found'}),
    );
    await settleVersion('1.2.6');
    expect(read(heaterHistorySupportedProvider), const AsyncData(true));

    await container
        .read(heaterHistoryRepositoryProvider)
        .fetch(1)
        .then((_) {}, onError: (_) {});
    await pumpEventQueue();

    expect(read(heaterHistorySupportedProvider), const AsyncData(false));
  });

  test('a 403 inside the AMS sheet leaves plain readings', () async {
    adapter.onGet(
      '/api/v1/ams-history/1/0',
      (s) => s.reply(403, {'detail': 'Forbidden'}),
    );
    expect(read(amsHistorySupportedProvider), const AsyncData(true));

    await container
        .read(amsHistoryRepositoryProvider)
        .fetch(1, 0)
        .then((_) {}, onError: (_) {});
    await pumpEventQueue();

    expect(read(amsHistorySupportedProvider), const AsyncData(false));
  });

  test('a drying listing that 404s hides the "later" modes', () async {
    adapter.onGet(
      '/api/v1/scheduled-dryings',
      (s) => s.reply(404, {'detail': 'Not Found'}),
    );
    expect(read(scheduledDryingSupportedProvider), const AsyncLoading<bool>());
    await settleVersion('1.2.6');
    expect(
      read(scheduledDryingSupportedProvider),
      const AsyncData(true),
      reason: 'before the listing, the version answers',
    );

    await container.read(scheduledDryingsProvider.future);
    await pumpEventQueue();

    expect(read(scheduledDryingSupportedProvider), const AsyncData(false));
  });

  test(
    'the chamber ceiling is 60 until the version is known, then 65',
    () async {
      // A value, not a gate: nothing may wait on it, so it has no loading state.
      container.listen(chamberMaxTargetProvider, (_, _) {});
      expect(container.read(chamberMaxTargetProvider), 60);

      await settleVersion('1.2.6');

      expect(container.read(chamberMaxTargetProvider), 65);
    },
  );
}
