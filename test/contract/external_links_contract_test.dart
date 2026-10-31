import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/external_link.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:bambuddy_mobile/data/external_links_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The sidebar links and the count an app reports for its own (server 1.2.6
/// dailies). The count is written by `PUT /external-links/badge`, which is for
/// the app behind a link, so the test plays that app with the admin's login.
/// Older servers have the links and no `badge_count`: that half skips there.
void main() {
  group('external links contract', skip: contractSkipReason, () {
    late Dio dio;
    late ExternalLinksRepository repo;
    late bool hasRoute;
    late int linkId;
    final url =
        'http://contract-links-${DateTime.now().microsecondsSinceEpoch}.lan:8080';

    setUpAll(() async {
      dio = await authenticatedDio();
      repo = ExternalLinksRepository(dio);
      final probe = await dio.get<dynamic>(
        Endpoints.externalLinks,
        options: Options(validateStatus: (_) => true),
      );
      hasRoute = probe.statusCode != 404;
      if (!hasRoute) return;
      final made = await dio.post<Map<String, dynamic>>(
        Endpoints.externalLinks,
        data: {'name': 'Contract orders', 'url': url, 'icon': 'link'},
      );
      linkId = made.data!['id'] as int;
    });

    tearDownAll(() async {
      if (!hasRoute) return;
      await dio.delete<dynamic>(
        '${Endpoints.externalLinks}$linkId',
        options: Options(validateStatus: (_) => true),
      );
    });

    bool skipOld() {
      if (!hasRoute) markTestSkipped('server predates external links');
      return !hasRoute;
    }

    Future<ExternalLink> mine() async =>
        (await repo.fetch()).firstWhere((l) => l.id == linkId);

    test('a server without the route reads as no links', () async {
      if (hasRoute) {
        markTestSkipped('server has external links');
        return;
      }
      expect(await repo.fetch(), isEmpty);
    });

    test('the list carries the fields the app reads', () async {
      if (skipOld()) return;
      final link = await mine();
      expect(link.name, 'Contract orders');
      expect(link.url, url);
      expect(link.hasCustomIcon, isFalse);
      expect(link.address, url.replaceFirst('http://', ''));
      // Nothing has reported yet, which an older server also says by omission.
      expect(link.badgeCount, isNull);
      expect(link.badge, 0);
    });

    test('a count the app reports is read back on its link', () async {
      if (skipOld()) return;
      final put = await dio.put<dynamic>(
        '${Endpoints.externalLinks}badge',
        data: {'url': url, 'count': 7},
        options: Options(validateStatus: (_) => true),
      );
      if (put.statusCode == 404 || put.statusCode == 405) {
        markTestSkipped('server predates link badges');
        return;
      }
      expect(put.statusCode, 200);
      final link = await mine();
      expect(link.badgeCount, 7);
      expect(link.badge, 7);
      expect(
        externalLinksBadgeTotal(await repo.fetch()),
        greaterThanOrEqualTo(7),
      );
    });

    test(
      'a user without external_links:read is refused, and reads none',
      () async {
        if (skipOld()) return;
        final viewer = await contractUser(dio, ['printers:read']);
        final res = await viewer.dio.get<dynamic>(
          Endpoints.externalLinks,
          options: Options(validateStatus: (_) => true),
        );
        expect(res.statusCode, 403);
        expect(await ExternalLinksRepository(viewer.dio).fetch(), isEmpty);
      },
    );

    test('a user holding it reads them', () async {
      if (skipOld()) return;
      final viewer = await contractUser(dio, [Permissions.externalLinksRead]);
      final links = await ExternalLinksRepository(viewer.dio).fetch();
      expect(links.any((l) => l.id == linkId), isTrue);
    });

    test('an API key with read-status reads them', () async {
      if (skipOld()) return;
      final keys = ApiKeysRepository(dio);
      final key = await keys.create(
        ApiKeyCreateInput(
          name: 'contract links',
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
      final asKey = ExternalLinksRepository(
        Dio(BaseOptions(baseUrl: contractBaseUrl))
          ..options.headers['X-API-Key'] = key.key,
      );
      expect((await asKey.fetch()).any((l) => l.id == linkId), isTrue);
    });
  });
}
