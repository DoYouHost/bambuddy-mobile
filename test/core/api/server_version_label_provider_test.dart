import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  /// A server that is unreachable for the first read and answers every one
  /// after it — the lift, and then the lobby.
  (Dio, int Function()) flakyServer() {
    var reads = 0;
    final dio = testDio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          reads++;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: reads == 1 ? 500 : 200,
              data: reads == 1 ? null : {'version': '1.2.6', 'repo': 'x/y'},
            ),
          );
        },
      ),
    );
    return (dio, () => reads);
  }

  /// Opens the drawer, waits for the line it shows, and closes it again.
  Future<String?> openAndCloseDrawer(ProviderContainer container) async {
    final sub = container.listen(serverVersionLabelProvider, (_, _) {});
    try {
      return await container.read(serverVersionLabelProvider.future);
    } finally {
      sub.close();
      // autoDispose runs on the next turn, not inside `close`.
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a drawer opened without a network asks again later', () async {
    // The regression this exists for: kept in the container, the provider
    // cached its first answer for the life of the process, so one opening in
    // a lift meant "unknown" until the app was killed — and the service's own
    // five-minute retry never ran, because nobody asked it a second time.
    final (dio, reads) = flakyServer();
    final container = ProviderContainer(
      overrides: [
        fakeServerProfileOverride(),
        serverVersionServiceProvider.overrideWithValue(
          ServerVersionService(dio),
        ),
      ],
    );
    addTearDown(container.dispose);

    final offline = DateTime(2026, 9, 11, 12);
    await withClock(
      Clock.fixed(offline),
      () async => expect(await openAndCloseDrawer(container), isNull),
    );

    // Inside the service's window the server is left alone, and the answer is
    // still unknown — the retry is the service's decision, not the drawer's.
    await withClock(
      Clock.fixed(offline.add(const Duration(minutes: 1))),
      () async => expect(await openAndCloseDrawer(container), isNull),
    );
    expect(reads(), 1, reason: 'the window is the service\'s to keep');

    await withClock(
      Clock.fixed(offline.add(const Duration(minutes: 6))),
      () async => expect(await openAndCloseDrawer(container), '1.2.6'),
    );
    expect(reads(), 2);
  });

  test('a version already read is not fetched again', () async {
    // The other half: re-opening the drawer must not put a request on the wire
    // every time. The service holds the cache, so the new provider gets its
    // answer without one.
    final (dio, reads) = flakyServer();
    final container = ProviderContainer(
      overrides: [
        fakeServerProfileOverride(),
        serverVersionServiceProvider.overrideWithValue(
          ServerVersionService(dio),
        ),
      ],
    );
    addTearDown(container.dispose);

    await openAndCloseDrawer(container); // fails, spends the first read
    await withClock(
      Clock.fixed(clock.now().add(const Duration(minutes: 6))),
      () async => expect(await openAndCloseDrawer(container), '1.2.6'),
    );
    expect(await openAndCloseDrawer(container), '1.2.6');
    expect(await openAndCloseDrawer(container), '1.2.6');

    expect(reads(), 2, reason: 'one failure, one success, then the cache');
  });

  test('an answer already had is there without a loading frame', () async {
    // The other failure this provider has to avoid: disposed on every close,
    // reopening the drawer starts at `AsyncLoading` again and the line reads
    // "Server …" for a frame in front of an answer the service already holds.
    // A success keeps its link, so the second opening has nothing to wait for.
    final (dio, reads) = flakyServer();
    final container = ProviderContainer(
      overrides: [
        fakeServerProfileOverride(),
        serverVersionServiceProvider.overrideWithValue(
          ServerVersionService(dio),
        ),
      ],
    );
    addTearDown(container.dispose);

    await openAndCloseDrawer(container); // fails, spends the first read
    await withClock(
      Clock.fixed(clock.now().add(const Duration(minutes: 6))),
      () async => expect(await openAndCloseDrawer(container), '1.2.6'),
    );

    final reopened = container.listen(serverVersionLabelProvider, (_, _) {});
    addTearDown(reopened.close);

    expect(
      container.read(serverVersionLabelProvider),
      isA<AsyncData<String?>>().having((v) => v.value, 'value', '1.2.6'),
      reason: 'the answer is there on the first frame, not after one',
    );
    expect(reads(), 2);
  });

  test('no server configured is not a version read', () async {
    // The router keeps every screen that shows this behind a profile, but the
    // provider is read from three of them now and `apiClientProvider` throws
    // without one — a guard is cheaper than trusting three routes.
    final (dio, reads) = flakyServer();
    final container = ProviderContainer(
      overrides: [
        noServerProfileOverride,
        serverVersionServiceProvider.overrideWithValue(
          ServerVersionService(dio),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(await openAndCloseDrawer(container), isNull);
    expect(reads(), 0);
  });
}
