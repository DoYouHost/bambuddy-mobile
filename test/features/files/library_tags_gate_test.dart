import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

/// The tag controls against what the catalog route answers. They are shown
/// while unknown, so what matters is what may take them away.
void main() {
  late DioAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    final dio = testDio();
    adapter = DioAdapter(dio: dio);
    container = ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(LibraryRepository(dio)),
      ],
    );
    addTearDown(container.dispose);
  });

  AsyncValue<bool> gate() => container.read(libraryTagsSupportedProvider);

  /// What the file manager does while it is on screen.
  Future<void> readCatalog() async {
    container.listen(libraryTagsSupportedProvider, (_, _) {});
    await container
        .read(libraryTagsProvider.future)
        .then((_) {}, onError: (_) {});
    await pumpEventQueue();
  }

  test('shown before anything has answered', () {
    expect(gate(), const AsyncData(true));
  });

  test('an older server takes them away', () async {
    adapter.onGet(
      '/api/v1/library/tags',
      (s) => s.reply(404, {'detail': 'Not Found'}),
    );
    await readCatalog();

    expect(gate(), const AsyncData(false));
  });

  test('a server with tags keeps them', () async {
    adapter.onGet('/api/v1/library/tags', (s) => s.reply(200, <dynamic>[]));
    await readCatalog();

    expect(gate(), const AsyncData(true));
  });

  test(
    'a refused session loses them, and the catalog still says why',
    () async {
      adapter.onGet(
        '/api/v1/library/tags',
        (s) => s.reply(403, {'detail': 'Forbidden'}),
      );
      await readCatalog();

      expect(gate(), const AsyncData(false));
      await expectLater(
        container.read(libraryTagsProvider.future),
        throwsA(anything),
        reason: 'a 403 is not "no catalog": the sheet shows the refusal',
      );
    },
  );

  test('a network failure leaves them where they were', () async {
    adapter.onGet(
      '/api/v1/library/tags',
      (s) => s.throws(
        0,
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/'),
          reason: 'offline',
        ),
      ),
    );
    await readCatalog();

    expect(gate(), const AsyncData(true));
  });
}
