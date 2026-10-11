import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/data/announcements_repository.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// Announcements from the Bambuddy maintainers (server 1.2.5.7). The feed is
/// signed and fetched from GitHub, so a test server's inbox holds whatever the
/// real feed holds — possibly nothing; what is pinned here is who may see it.
void main() {
  group('announcements contract', skip: contractSkipReason, () {
    late Dio dio;
    late AnnouncementsRepository repo;
    late bool hasRoute;

    setUpAll(() async {
      dio = await authenticatedDio();
      repo = AnnouncementsRepository(dio);
      final res = await dio.get<dynamic>(
        Endpoints.announcements,
        options: Options(validateStatus: (_) => true),
      );
      hasRoute = res.statusCode != 404;
    });

    bool skipOld() {
      if (!hasRoute) markTestSkipped('server predates announcements');
      return !hasRoute;
    }

    test('an older server answers 404, which reads as no inbox', () async {
      if (hasRoute) {
        markTestSkipped('server has announcements');
        return;
      }
      expect((await repo.fetch()).visible, isFalse);
    });

    test('an admin sees the inbox, in the shape the app reads', () async {
      if (skipOld()) return;
      final res = await dio.get<Map<String, dynamic>>(Endpoints.announcements);
      final body = res.data!;
      expect(body['visible'], isTrue);
      expect(body['announcements'], isA<List<dynamic>>());
      for (final a in body['announcements'] as List<dynamic>) {
        expect(
          (a as Map<String, dynamic>).keys,
          containsAll(['id', 'level', 'texts', 'archived', 'read']),
        );
      }
      expect((await repo.fetch()).visible, isTrue);
    });

    test('marking an unknown id read is a 404, not a silent yes', () async {
      if (skipOld()) return;
      await expectLater(
        repo.markRead('contract-no-such-id'),
        throwsA(isA<AppApiException>()),
      );
    });

    test('a non-admin gets no inbox while it is not shared', () async {
      if (skipOld()) return;
      final viewer = await contractUser(dio, ['printers:read']);
      expect(
        (await AnnouncementsRepository(viewer.dio).fetch()).visible,
        isFalse,
      );
    });

    test('an API key never gets one', () async {
      if (skipOld()) return;
      final keys = ApiKeysRepository(dio);
      final key = await keys.create(
        ApiKeyCreateInput(
          name: 'contract announcements',
          scopes: {ApiKeyScope.readStatus},
        ),
      );
      addTearDown(
        () => dio.delete<dynamic>(
          Endpoints.apiKeyById(key.apiKey.id),
          options: Options(validateStatus: (_) => true),
        ),
      );
      await pollUntil(
        'key ${key.apiKey.id} to be committed',
        () async =>
            (await keys.list()).any((k) => k.id == key.apiKey.id) ? true : null,
        within: const Duration(seconds: 10),
        every: const Duration(milliseconds: 100),
      );
      final asKey = AnnouncementsRepository(
        Dio(BaseOptions(baseUrl: contractBaseUrl))
          ..options.headers['X-API-Key'] = key.key,
      );
      expect((await asKey.fetch()).visible, isFalse);
    });
  });
}
