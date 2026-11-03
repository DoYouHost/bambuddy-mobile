import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/data/external_links_repository.dart';
import 'package:bambuddy_mobile/features/links/external_links_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  final dio = testDio();
  final server = mockServer(dio);
  late RequestLog log;

  setUp(() {
    log = captureRequests(dio);
    server.onGet(
      '/api/v1/external-links/',
      (s) => s.reply(200, [
        {'id': 1, 'name': 'A', 'url': 'http://a.lan', 'badge_count': 2},
      ]),
    );
  });

  ProviderContainer container({bool? canRead, bool profile = true}) {
    final c = ProviderContainer(
      retry: neverRetry,
      overrides: [
        profile ? fakeServerProfileOverride() : noServerProfileOverride,
        externalLinksRepositoryProvider.overrideWithValue(
          ExternalLinksRepository(dio),
        ),
        if (canRead != null)
          permissionProvider(
            Permissions.externalLinksRead,
          ).overrideWithValue(canRead),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('reads the links for a session that may', () async {
    final c = container(canRead: true);
    expect((await c.read(externalLinksProvider.future)).single.badge, 2);
  });

  test('a session /auth/me says may not read them sends no request', () async {
    final c = container(canRead: false);
    expect(await c.read(externalLinksProvider.future), isEmpty);
    expect(log.calls, isEmpty);
  });

  test('without a server profile there is nothing to ask', () async {
    final c = container(canRead: true, profile: false);
    expect(await c.read(externalLinksProvider.future), isEmpty);
    expect(log.calls, isEmpty);
  });

  test('a regained contact reads the counts again', () async {
    final c = container(canRead: true);
    await c.read(externalLinksProvider.future);
    c.read(serverContactEpochProvider.notifier).bump();
    await c.read(externalLinksProvider.future);
    expect(log.calls, hasLength(2));
  });
}
